# Resend Email Integration

**Status:** Implemented
**Completed:** 2025-11-24

## Summary

Resend is configured as the production email provider for authentication emails. The integration uses Swoosh's adapter system for seamless switching between environments.

## Configuration

### Production
- **Adapter:** `Resend.Swoosh.Adapter`
- **From Address:** `SENDER_EMAIL` env var
- **Sender Name:** `APP_NAME` env var
- **Domain:** the domain of `SENDER_EMAIL` (must be verified in Resend)

### Environment Variables

Set in production:
```bash
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Development
- Uses `Swoosh.Adapters.Local`
- Emails viewable at `/dev/mailbox`

### Test
- Uses `Swoosh.Adapters.Test`
- No changes to test assertions needed

## Email Types

The following Phoenix authentication emails are sent via Resend in production:

1. **Magic Link Login** - `deliver_magic_link_instructions/2`
2. **Email Confirmation** - `deliver_confirmation_instructions/2`
3. **Email Update Instructions** - `deliver_update_email_instructions/2`

## Files Modified

- `mix.exs` - Added `{:resend, "~> 0.4.4"}` dependency
- `config/runtime.exs` - Resend adapter configuration for production
- `lib/coin_tracker/accounts/user_notifier.ex` - Updated from address

## Future Enhancements

Optional features that can be added later:
- HTML email templates (currently plain text)
- Subscription lifecycle emails
- Trading alert emails
- Webhook endpoint for delivery tracking
- Email bounce handling
