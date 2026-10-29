-- Match Korean card-name conditions against their Japanese and romanized card data.
-- In particular, B10068's bond condition is 후루야 레이 (降谷零), not the source card name.
CREATE OR REPLACE FUNCTION public.private_card_effect_name_matches_v1(p_card jsonb, p_expected text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v text := lower(coalesce(p_expected, ''));
  j text := lower(coalesce(p_card, '{}'::jsonb)::text);
BEGIN
  IF v = '' THEN RETURN false; END IF;
  IF position(v in j)>0 THEN RETURN true; END IF;

  IF v IN ('工藤新一','쿠도 신이치','쿠도신이치','kudo shinichi','kudou shinichi','shinichi kudo') THEN
    RETURN position('工藤新一' in j)>0 OR position('쿠도 신이치' in j)>0
      OR position('kudo shinichi' in j)>0 OR position('kudou shinichi' in j)>0;
  END IF;
  IF v IN ('大和敢助','야마토 칸스케','야마토칸스케','yamato kansuke') THEN
    RETURN position('大和敢助' in j)>0 OR position('야마토 칸스케' in j)>0 OR position('yamato kansuke' in j)>0;
  END IF;
  IF v IN ('降谷零','降谷 零','후루야 레이','후루야레이','furuya rei','rei furuya') THEN
    RETURN position('降谷零' in j)>0 OR position('降谷 零' in j)>0
      OR position('후루야 레이' in j)>0 OR position('후루야레이' in j)>0
      OR position('furuya rei' in j)>0 OR position('rei furuya' in j)>0;
  END IF;
  IF v IN ('諸伏景光','諸伏 景光','모로후시 히로미츠','모로후시 히로미쓰','모로후시히로미츠','hiromitsu morofushi','morofushi hiromitsu') THEN
    RETURN position('諸伏景光' in j)>0 OR position('諸伏 景光' in j)>0
      OR position('모로후시 히로미츠' in j)>0 OR position('모로후시 히로미쓰' in j)>0
      OR position('모로후시히로미츠' in j)>0
      OR position('hiromitsu morofushi' in j)>0 OR position('morofushi hiromitsu' in j)>0;
  END IF;
  IF v IN ('伊達航','伊達 航','다테 와타루','다테와타루','wataru date','date wataru') THEN
    RETURN position('伊達航' in j)>0 OR position('伊達 航' in j)>0
      OR position('다테 와타루' in j)>0 OR position('다테와타루' in j)>0
      OR position('wataru date' in j)>0 OR position('date wataru' in j)>0;
  END IF;
  IF v IN ('萩原研二','萩原 研二','하기와라 켄지','하기와라켄지','kenji hagiwara','hagiwara kenji') THEN
    RETURN position('萩原研二' in j)>0 OR position('萩原 研二' in j)>0
      OR position('하기와라 켄지' in j)>0 OR position('하기와라켄지' in j)>0
      OR position('kenji hagiwara' in j)>0 OR position('hagiwara kenji' in j)>0;
  END IF;
  IF v IN ('松田陣平','松田 陣平','마츠다 진페이','마츠다진페이','jinpei matsuda','matsuda jinpei') THEN
    RETURN position('松田陣平' in j)>0 OR position('松田 陣平' in j)>0
      OR position('마츠다 진페이' in j)>0 OR position('마츠다진페이' in j)>0
      OR position('jinpei matsuda' in j)>0 OR position('matsuda jinpei' in j)>0;
  END IF;
  IF v IN ('工藤優作','工藤 優作','쿠도 유사쿠','쿠도유사쿠','yusaku kudo','kudo yusaku') THEN
    RETURN position('工藤優作' in j)>0 OR position('工藤 優作' in j)>0
      OR position('쿠도 유사쿠' in j)>0 OR position('쿠도유사쿠' in j)>0
      OR position('yusaku kudo' in j)>0 OR position('kudo yusaku' in j)>0;
  END IF;
  IF v IN ('黒羽盗一','黑羽盗一','쿠로바 도이치','쿠로바도이치','toichi kuroba','kuroba toichi') THEN
    RETURN position('黒羽盗一' in j)>0 OR position('黑羽盗一' in j)>0
      OR position('쿠로바 도이치' in j)>0 OR position('쿠로바도이치' in j)>0
      OR position('toichi kuroba' in j)>0 OR position('kuroba toichi' in j)>0;
  END IF;
  IF v IN ('工藤有希子','工藤 有希子','쿠도 유키코','쿠도유키코','yukiko kudo','kudo yukiko') THEN
    RETURN position('工藤有希子' in j)>0 OR position('工藤 有希子' in j)>0
      OR position('쿠도 유키코' in j)>0 OR position('쿠도유키코' in j)>0
      OR position('yukiko kudo' in j)>0 OR position('kudo yukiko' in j)>0;
  END IF;
  RETURN false;
END
$function$;
