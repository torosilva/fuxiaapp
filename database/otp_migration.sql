-- OTP verifications table for WhatsApp auth
CREATE TABLE otp_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookup by phone
CREATE INDEX idx_otp_phone ON otp_verifications (phone);

-- Auto-delete expired OTPs after 1 hour (keeps table clean)
CREATE OR REPLACE FUNCTION delete_expired_otps() RETURNS void AS $$
  DELETE FROM otp_verifications WHERE expires_at < NOW() - INTERVAL '1 hour';
$$ LANGUAGE SQL;
