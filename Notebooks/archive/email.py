import smtplib
from email.mime.text import MIMEText

# ---- Service account credentials (TEST ONLY - move to Key Vault for production) ----
sender   = "svc-monitoring@yourdomain.com"   # Service account UPN (must have Exchange Online mailbox)
receiver = "you@yourdomain.com"
password = ""                                # Service account password

subject = "Test Email"
body    = "Hello, this is a test email sent from Python via Microsoft 365 SMTP."

# Build message
msg = MIMEText(body)
msg["Subject"] = subject
msg["From"]    = sender
msg["To"]      = receiver

# Send via Microsoft 365 SMTP relay
# Required tenant config:
#   - SMTP AUTH enabled tenant-wide:  Set-TransportConfig -SmtpClientAuthenticationDisabled $false
#   - SMTP AUTH enabled per mailbox:  Set-CASMailbox <user> -SmtpClientAuthenticationDisabled $false
#   - Account excluded from any "block legacy auth" Conditional Access policy
#   - MFA disabled / not enforced for this account
# Endpoint: smtp.office365.com on port 587 with STARTTLS (NOT SMTP_SSL on 465 -- that is not supported)
try:
    with smtplib.SMTP("smtp.office365.com", 587, timeout=30) as server:
        server.set_debuglevel(1)   # prints SMTP conversation; set to 0 once it works
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(sender, password)
        server.send_message(msg)
        print("Email sent successfully.")
except smtplib.SMTPAuthenticationError as e:
    print(f"AUTH FAILED ({e.smtp_code}): {e.smtp_error.decode(errors='ignore') if isinstance(e.smtp_error, bytes) else e.smtp_error}")
    print("Common causes:")
    print("  535 5.7.139 SmtpClientAuthentication is disabled for the Tenant   -> enable tenant-wide SMTP AUTH")
    print("  535 5.7.139 Authentication unsuccessful, ... mailbox              -> enable SMTP AUTH on this mailbox")
    print("  535 5.7.3  Authentication unsuccessful                            -> wrong password / blocked by Conditional Access")
except smtplib.SMTPException as e:
    print(f"SMTP error: {type(e).__name__}: {e}")
