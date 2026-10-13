-- Seed/demo schema and data for runtime-evidence workflow
-- Idempotent: safe to run multiple times
-- Creates a small tenant + tenant_data example and a simple PL/pgSQL function.
BEGIN;

-- Create tenants table
CREATE TABLE IF NOT EXISTS tenants (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL
);

-- Create tenant_data table
CREATE TABLE IF NOT EXISTS tenant_data (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES tenants(id),
  info TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Insert two demo tenants (use fixed UUIDs so tests can refer to them)
INSERT INTO tenants (id, name)
SELECT t.id, t.name
FROM (VALUES
  ('11111111-1111-1111-1111-111111111111'::uuid, 'tenant_a'),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'tenant_b')
) AS t(id, name)
LEFT JOIN tenants existing ON existing.id = t.id
WHERE existing.id IS NULL;

-- Insert demo rows for tenant_a only (idempotent)
INSERT INTO tenant_data (id, tenant_id, info)
SELECT d.id, d.tenant_id, d.info
FROM (VALUES
  ('a1111111-1111-1111-1111-111111111111'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Alice - invoice #1001'),
  ('a2222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'Alice - invoice #1002')
) AS d(id, tenant_id, info)
LEFT JOIN tenant_data existing ON existing.id = d.id
WHERE existing.id IS NULL;

-- Ensure RLS is enabled and a policy exists that restricts rows to the current tenant.
-- Policy uses current_setting('app.current_tenant', true) which returns NULL if not set.
ALTER TABLE tenant_data ENABLE ROW LEVEL SECURITY;

-- Replace the policy each run so it's predictable and idempotent
DROP POLICY IF EXISTS tenant_isolation ON tenant_data;
CREATE POLICY tenant_isolation ON tenant_data
  USING ( tenant_id::text = current_setting('app.current_tenant', true) );

-- Create a simple function that returns tenant_data rows (will be subject to RLS)
CREATE OR REPLACE FUNCTION get_tenant_data()
  RETURNS TABLE(id UUID, tenant_id UUID, info TEXT, created_at TIMESTAMPTZ)
AS $$
BEGIN
  RETURN QUERY SELECT id, tenant_id, info, created_at FROM tenant_data ORDER BY created_at;
END;
$$ LANGUAGE plpgsql STABLE;

COMMIT;