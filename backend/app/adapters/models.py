"""Per-invocation Pydantic AI models and exact-model speech protocol adapters."""

import io
from dataclasses import dataclass
from typing import Literal, cast

import httpx2 as httpx
from google.genai.types import HttpRetryOptions
from openai import AsyncOpenAI
from PIL import Image
from pydantic import BaseModel, SecretStr
from pydantic_ai import Agent, BinaryContent, NativeOutput
from pydantic_ai.exceptions import UnexpectedModelBehavior, UsageLimitExceeded
from pydantic_ai.models.google import GoogleModel
from pydantic_ai.models.openrouter import OpenRouterModel, OpenRouterModelSettings
from pydantic_ai.models.test import TestModel
from pydantic_ai.providers.google import GoogleProvider
from pydantic_ai.providers.openrouter import OpenRouterProvider
from pydantic_ai.usage import UsageLimits

from app.core.settings import Settings
from app.schemas.model_settings import CredentialTest, ModelLimits
from app.services.model_configuration import TEXT_MODEL, TTS_MODEL


class ProbeOutput(BaseModel):
    ok: Literal[True]
    color: Literal["red"] | None = None


@dataclass(frozen=True)
class ModelOutcome:
    usage: dict[str, int | None]
    usage_schema: str
    simulated: bool


class ProviderFailure(Exception):
    def __init__(self, code: str, *, unknown: bool = False, facts: ModelOutcome | None = None):
        super().__init__(code)
        self.code = code
        self.unknown = unknown
        self.facts = facts


def test_image() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (16, 16), (255, 0, 0)).save(output, format="PNG")
    return output.getvalue()


class ModelFactory:
    """Pydantic model construction with explicit invocation-owned clients/keys."""

    @staticmethod
    def openrouter(model_id: str, client: AsyncOpenAI) -> OpenRouterModel:
        if model_id != TEXT_MODEL:
            raise ProviderFailure("CAPABILITY_UNSUPPORTED")
        return OpenRouterModel(model_id, provider=OpenRouterProvider(openai_client=client))

    @staticmethod
    def gemini(model_id: str, key: SecretStr) -> GoogleModel:
        return GoogleModel(
            model_id,
            provider=GoogleProvider(
                api_key=key.get_secret_value(), retry_options=HttpRetryOptions(attempts=1)
            ),
        )

    @staticmethod
    def simulated(settings: Settings, capability: str) -> TestModel:
        if settings.app_env not in {"dev", "test"} or settings.model_execution_mode != "fake":
            raise ProviderFailure("FAKE_FORBIDDEN")
        return TestModel(
            custom_output_args={"ok": True, "color": "red"}
            if capability == "vision"
            else {"ok": True}
        )


async def execute_probe(
    settings: Settings,
    provider: str,
    key: SecretStr,
    config: CredentialTest,
    limits: ModelLimits | None = None,
) -> ModelOutcome:
    """One attempt, no SDK retries, no tools, no implicit provider fallback."""
    if settings.model_execution_mode == "disabled":
        raise ProviderFailure("MODEL_EXECUTION_DISABLED")
    limits = limits or ModelLimits()
    fake = settings.model_execution_mode == "fake"
    if fake and settings.app_env not in {"dev", "test"}:
        raise ProviderFailure("FAKE_FORBIDDEN")
    if config.capability == "tts":
        if provider != "openrouter" or config.model_id != TTS_MODEL or config.voice_id != "Kore":
            raise ProviderFailure("CAPABILITY_UNSUPPORTED")
        if fake:
            return ModelOutcome({"input_characters": 5}, "simulated-speech-v1", True)
        return await speech_probe(key, config, limits.tts_timeout_seconds)
    timeout = limits.timeout_seconds
    if fake:
        model = ModelFactory.simulated(settings, config.capability)
        agent = Agent(model, output_type=ProbeOutput, retries=0)
        result = await agent.run(
            "Fixed capability probe", usage_limits=UsageLimits(request_limit=1, tool_calls_limit=0)
        )
        usage = result.usage
        return ModelOutcome(
            {
                "input_tokens": usage.input_tokens,
                "output_tokens": usage.output_tokens,
                "cache_read_tokens": usage.cache_read_tokens,
                "cache_write_tokens": usage.cache_write_tokens,
            },
            "simulated-pydantic-v1",
            True,
        )
    reported: dict[str, int | None] = {}

    async def capture_usage(response: httpx.Response) -> None:
        if response.status_code == 200:
            await response.aread()
            try:
                value: object = response.json()
                if isinstance(value, dict):
                    raw = cast(dict[str, object], value).get("usage")
                    if isinstance(raw, dict):
                        reported.update(normalize_usage(cast(dict[str, object], raw)))
            except ValueError:
                return

    async with httpx.AsyncClient(
        timeout=timeout, follow_redirects=False, event_hooks={"response": [capture_usage]}
    ) as http_client:
        if provider == "openrouter":
            if config.model_id != TEXT_MODEL:
                raise ProviderFailure("CAPABILITY_UNSUPPORTED")
            async with AsyncOpenAI(
                api_key=key.get_secret_value(),
                base_url="https://openrouter.ai/api/v1",
                max_retries=0,
                http_client=http_client,
            ) as client:
                model = ModelFactory.openrouter(config.model_id, client)
                agent = Agent(
                    model,
                    output_type=NativeOutput(ProbeOutput),
                    retries=0,
                    model_settings=OpenRouterModelSettings(
                        max_tokens=limits.max_output_tokens,
                        timeout=timeout,
                        openrouter_provider={
                            "allow_fallbacks": False,
                            "require_parameters": True,
                        },
                    ),
                )
                try:
                    await run_probe(agent, config)
                except (UnexpectedModelBehavior, UsageLimitExceeded, ProviderFailure):
                    raise ProviderFailure(
                        "OUTPUT_INVALID",
                        facts=ModelOutcome(reported, "openrouter-chat-usage-v1", False),
                    ) from None
                return ModelOutcome(reported, "openrouter-chat-usage-v1", False)
        if provider == "gemini":
            # Entry retained but release catalog remains disabled until separately
            # authorized real protocol verification. No OpenRouter fallback.
            model = ModelFactory.gemini(config.model_id, key)
            agent = Agent(
                model,
                output_type=NativeOutput(ProbeOutput),
                retries=0,
                model_settings={"max_tokens": limits.max_output_tokens, "timeout": timeout},
            )
            return await run_probe(agent, config)
        raise ProviderFailure("CAPABILITY_UNSUPPORTED")


async def run_probe(agent: Agent[object, ProbeOutput], config: CredentialTest) -> ModelOutcome:
    prompt = "Return the JSON object with ok=true."
    content: str | list[str | BinaryContent] = prompt
    if config.capability == "vision":
        content = [
            "Identify the square color. Return ok=true and color='red' if it is red.",
            BinaryContent(test_image(), media_type="image/png"),
        ]
    result = await agent.run(content, usage_limits=UsageLimits(request_limit=1, tool_calls_limit=0))
    if config.capability == "vision" and result.output.color != "red":
        raise ProviderFailure("OUTPUT_INVALID")
    usage = result.usage
    return ModelOutcome(
        {
            "input_tokens": usage.input_tokens,
            "output_tokens": usage.output_tokens,
            "cache_read_tokens": usage.cache_read_tokens,
            "cache_write_tokens": usage.cache_write_tokens,
        },
        "pydantic-ai-openrouter-v1",
        False,
    )


async def speech_probe(
    key: SecretStr, config: CredentialTest, deadline_seconds: int = 90
) -> ModelOutcome:
    sample = "こんにちは。" if config.language_tag == "ja" else "Hello."
    async with (
        httpx.AsyncClient(timeout=deadline_seconds, follow_redirects=False) as client,
        client.stream(
            "POST",
            "https://openrouter.ai/api/v1/audio/speech",
            headers={"Authorization": "Bearer " + key.get_secret_value()},
            json={
                "model": config.model_id,
                "input": sample,
                "voice": "Kore",
                "response_format": "mp3",
                "provider": {"allow_fallbacks": False},
            },
        ) as response,
    ):
        if response.status_code != 200:
            raise ProviderFailure(http_error_code(response.status_code))
        if response.headers.get("content-type", "").split(";")[0] != "audio/mpeg":
            raise ProviderFailure("OUTPUT_INVALID")
        buffer = bytearray()
        async for chunk in response.aiter_bytes():
            buffer.extend(chunk)
            if len(buffer) > 1024 * 1024:
                raise ProviderFailure("OUTPUT_INVALID")
        # Actual MP3 frame validation, including a complete frame after ID3.
        validate_mp3(bytes(buffer))
    return ModelOutcome({"input_characters": len(sample)}, "openrouter-speech-v1", False)


def validate_mp3(data: bytes) -> None:
    offset = 0
    if data.startswith(b"ID3"):
        if len(data) < 10 or any(value & 128 for value in data[6:10]):
            raise ProviderFailure("OUTPUT_INVALID")
        size = sum(value << (7 * (3 - index)) for index, value in enumerate(data[6:10]))
        offset = 10 + size
    frames = 0
    while offset + 4 <= len(data):
        header = int.from_bytes(data[offset : offset + 4], "big")
        if header >> 21 != 0x7FF:
            # ID3v1 trailer is the sole allowed nonframe tail.
            if len(data) - offset == 128 and data[offset : offset + 3] == b"TAG":
                offset = len(data)
                break
            raise ProviderFailure("OUTPUT_INVALID")
        version, layer = (header >> 19) & 3, (header >> 17) & 3
        bitrate_index, sample_index = (header >> 12) & 15, (header >> 10) & 3
        if version == 1 or layer != 1 or bitrate_index in (0, 15) or sample_index == 3:
            raise ProviderFailure("OUTPUT_INVALID")
        rates = (44100, 48000, 32000)
        sample_rate = rates[sample_index] // (1 if version == 3 else 2 if version == 2 else 4)
        bitrates = (
            (0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
            if version == 3
            else (0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)
        )
        frame_size = (144 if version == 3 else 72) * bitrates[
            bitrate_index
        ] * 1000 // sample_rate + ((header >> 9) & 1)
        if offset + frame_size > len(data):
            raise ProviderFailure("OUTPUT_INVALID")
        offset += frame_size
        frames += 1
    if frames < 2 or offset != len(data):
        raise ProviderFailure("OUTPUT_INVALID")


def http_error_code(status: int) -> str:
    return {
        401: "KEY_REJECTED",
        403: "KEY_REJECTED",
        404: "MODEL_UNAVAILABLE",
        402: "PROVIDER_LIMIT",
        429: "PROVIDER_RATE_LIMIT",
    }.get(status, "PROVIDER_ERROR")


def normalize_usage(raw: dict[str, object]) -> dict[str, int | None]:
    """Only actually reported numeric fields; absent SDK zero defaults stay NULL."""
    output: dict[str, int | None] = {}
    for supplier, local in (
        ("prompt_tokens", "input_tokens"),
        ("completion_tokens", "output_tokens"),
        ("total_tokens", "total_tokens"),
    ):
        value = raw.get(supplier)
        if isinstance(value, int) and not isinstance(value, bool) and 0 <= value < 2**63:
            output[local] = value
    for container, key, local in (
        ("prompt_tokens_details", "cached_tokens", "cache_read_tokens"),
        ("prompt_tokens_details", "cache_write_tokens", "cache_write_tokens"),
        ("completion_tokens_details", "reasoning_tokens", "reasoning_tokens"),
        ("prompt_tokens_details", "audio_tokens", "input_audio_tokens"),
        ("completion_tokens_details", "audio_tokens", "output_audio_tokens"),
    ):
        details = raw.get(container)
        if isinstance(details, dict):
            value = cast(dict[str, object], details).get(key)
            if isinstance(value, int) and not isinstance(value, bool) and 0 <= value < 2**63:
                output[local] = value
    return output
