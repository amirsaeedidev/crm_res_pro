-- Phase 11 security hardening.
-- These routines are trigger functions only; clients must not invoke them through PostgREST RPC.
-- PostgreSQL trigger execution does not require the calling API role to retain EXECUTE.
REVOKE EXECUTE ON FUNCTION public.reconcile_discount_campaign_sms_link() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_discount_campaign_sms_result() FROM PUBLIC, anon, authenticated;
