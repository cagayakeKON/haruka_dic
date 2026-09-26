"""Narrow SMTP transport for one validated mailbox and one action link."""

import smtplib
import ssl
from email.headerregistry import Address
from email.message import EmailMessage

from app.core.settings import Settings


def send_smtp_message(settings: Settings, email: str, link: str, purpose: str) -> None:
    if settings.app_env == "test" and not email.lower().endswith(".example.test"):
        raise ValueError("isolated mail transport only permits test recipients")
    if not settings.smtp_host or not settings.smtp_from:
        raise ValueError("mail transport is unconfigured")
    message = EmailMessage()
    from_local, from_domain = settings.smtp_from.split("@", 1)
    to_local, to_domain = email.split("@", 1)
    message["From"] = Address(username=from_local, domain=from_domain)
    message["To"] = Address(username=to_local, domain=to_domain)
    message["Subject"] = "Haruka 邮箱验证" if purpose == "email_verify" else "Haruka 密码找回"
    message.set_content(f"请在有效期内打开以下链接并确认操作：\n{link}\n")
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=5) as smtp:
        if settings.smtp_starttls:
            smtp.starttls(context=ssl.create_default_context())
        if settings.smtp_username and settings.smtp_password:
            smtp.login(settings.smtp_username, settings.smtp_password.get_secret_value())
        smtp.send_message(message, from_addr=settings.smtp_from, to_addrs=[email])
