"""Bounded MinIO SDK calls on a dedicated lane; no bucket creation at startup."""

from functools import partial
from io import BytesIO
from urllib.parse import urlsplit

from minio import Minio
from urllib3 import PoolManager, Retry, Timeout

from app.adapters.blocking import BlockingClient
from app.core.settings import InfrastructureSettings


class ObjectStorage:
    def __init__(self, settings: InfrastructureSettings) -> None:
        endpoint = urlsplit(settings.s3_endpoint)
        self.bucket = settings.s3_bucket
        self._pool = PoolManager(
            num_pools=2,
            maxsize=4,
            timeout=Timeout(connect=3, read=5),
            retries=Retry(total=0),
        )
        self._client = Minio(
            endpoint.netloc,
            access_key=settings.s3_access_key.get_secret_value(),
            secret_key=settings.s3_secret_key.get_secret_value(),
            secure=endpoint.scheme == "https",
            region="us-east-1",
            http_client=self._pool,
        )
        self._lane = BlockingClient("s3")

    async def check(self) -> None:
        if not await self._lane.call(partial(self._client.bucket_exists, self.bucket)):
            raise RuntimeError("configured private bucket is missing")

    async def put(self, key: str, data: bytes) -> None:
        """Internal transport; service must authorize owner and final-object publication."""
        await self._lane.call(
            partial(self._client.put_object, self.bucket, key, BytesIO(data), len(data))
        )

    async def get(self, key: str) -> bytes:
        def read() -> bytes:
            response = self._client.get_object(self.bucket, key)
            try:
                return response.read()
            finally:
                response.close()
                response.release_conn()

        return await self._lane.call(read)

    async def remove(self, key: str) -> None:
        await self._lane.call(partial(self._client.remove_object, self.bucket, key))

    async def aclose(self) -> None:
        await self._lane.close(self._pool.clear)
