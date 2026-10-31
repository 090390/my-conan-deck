-- Treat the Korean and Japanese Police trait names as equivalent in effect filters.
BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_has_trait_v1(p_card jsonb, p_trait text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE j text := lower(coalesce(p_card, '{}'::jsonb)::text); t text := lower(coalesce(p_trait,''));
BEGIN
  IF t IN ('少年探偵団','소년탐정단','detective boys') THEN
    RETURN position('少年探偵団' in j)>0 OR position('소년탐정단' in j)>0 OR position('detective boys' in j)>0;
  ELSIF t IN ('神奈川県警','가나가와현 경찰','가나가와현경','kanagawa prefectural police') THEN
    RETURN position('神奈川県警' in j)>0 OR position('가나가와현 경찰' in j)>0 OR position('가나가와현경' in j)>0;
  ELSIF t IN ('警察','경찰','police') THEN
    RETURN position('警察' in j)>0 OR position('경찰' in j)>0 OR position('police' in j)>0;
  ELSIF t IN ('長野県警','나가노현 경찰','나가노현경','nagano prefectural police') THEN
    RETURN position('長野県警' in j)>0 OR position('나가노현 경찰' in j)>0 OR position('나가노현경' in j)>0;
  END IF;
  RETURN position(t in j)>0;
END
$function$;

COMMIT;
