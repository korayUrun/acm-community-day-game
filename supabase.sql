-- =====================================================================
-- Debug Ördeği – MSKÜ ACM Community Day
-- Supabase şeması: tablolar, RLS, yetkiler ve RPC fonksiyonları.
--
-- Kullanım: Supabase panelinde SQL Editor'a yapıştırıp çalıştırın.
-- Dosya tekrar çalıştırılabilir; yeni yapıdaki mevcut veriyi silmez.
--
-- Değişiklik notları:
--   2026-10-12  İlk sürüm: players, scores, register_player,
--               submit_score, leaderboard.
--   2026-10-12  player_rank eklendi (oyun bitti ekranındaki sıra için).
--   2026-10-12  Silme örneği temizlik.sql dosyasına taşındı.
--   2026-10-12  Oyuncu kimliği Instagram kullanıcı adına geçirildi.
--               players tablosu eski yapıdaysa (instagram sütunu yoksa)
--               scores ile birlikte bir kez silinip yeniden kurulur
--               (eski veriler sadece test verisiydi). Eski 3 parametreli
--               register_player kaldırıldı; yenisi register_player(p_instagram).
--               leaderboard artık "@kullaniciadi" döndürür.
--   2026-10-12  Oyun adı "Debug Ördeği" oldu (sadece yorum; şema değişmedi).
--   2026-10-12  players tablosuna full_name (ad soyad) eklendi; sadece ödül
--               verirken kişiyi doğrulamak için, hiçbir RPC çıktısında yok.
--               full_name sütunu olmayan eski tablo (test verisi) scores ile
--               birlikte bir kez silinip yeniden kurulur. register_player artık
--               (p_instagram, p_full_name); tek parametreli eski sürüm kaldırıldı.
--   2026-10-13  player_rank artık (rank, total, best) döndürür: oyuncunun en iyi
--               skoru da gelir. Dönüş tipi değiştiği için önce drop edilir.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0) Eski yapıdan geçiş (tek seferlik)
--    players tablosunda instagram veya full_name sütunu yoksa eski yapıdadır:
--    scores ile birlikte silinir (eski veriler sadece test verisi). Yeni yapı
--    kurulduktan sonra bu blok bir şey yapmaz, yani dosyayı etkinlik sırasında
--    tekrar çalıştırmak veriyi silmez.
-- ---------------------------------------------------------------------

do $$
begin
  if exists (
       select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'players'
     )
     and (
       not exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'players' and column_name = 'instagram'
       )
       or not exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'players' and column_name = 'full_name'
       )
     )
  then
    drop table if exists public.scores;
    drop table public.players;
  end if;
end
$$;

-- Eski kayıt fonksiyonları kaldırılır; yoksa farklı sürümler yan yana kalır.
drop function if exists public.register_player(text, text, boolean);
drop function if exists public.register_player(text);

-- ---------------------------------------------------------------------
-- 1) Tablolar
-- ---------------------------------------------------------------------

-- Oyuncular: Instagram kullanıcı adı benzersizdir; küçük harf, 1-30
-- karakter, sadece a-z 0-9 . _ . full_name (ad soyad) 2-40 karakter, baş ve
-- sonunda boşluk yok; sadece ödül verirken doğrulama için tutulur, hiçbir
-- ekranda gösterilmez. KVKK onayı olmadan kayıt olamaz.
-- last_score_at, "3 saniyede en fazla 1 skor" kuralı için kullanılır.
create table if not exists public.players (
  id             uuid        primary key default gen_random_uuid(),
  instagram      text        not null unique check (instagram ~ '^[a-z0-9._]{1,30}$'),
  full_name      text        not null check (char_length(full_name) between 2 and 40 and full_name = btrim(full_name)),
  kvkk_consent   boolean     not null check (kvkk_consent),
  created_at     timestamptz not null default now(),
  last_score_at  timestamptz
);

-- Skorlar: her oyun bir satır. Oyuncu silinirse skorları da silinir.
create table if not exists public.scores (
  id          bigint generated always as identity primary key,
  player_id   uuid        not null references public.players(id) on delete cascade,
  score       int         not null check (score between 0 and 300),
  created_at  timestamptz not null default now()
);

-- Skor tablosu sorgusunu hızlandıran indeksler.
create index if not exists scores_player_score_idx on public.scores (player_id, score desc, created_at);
create index if not exists scores_score_idx        on public.scores (score desc);

-- ---------------------------------------------------------------------
-- 2) RLS ve tablo yetkileri
--    RLS açık, hiç policy yok; anon/authenticated tablolara hiç
--    erişemez. Erişim sadece aşağıdaki security definer fonksiyonlarla.
-- ---------------------------------------------------------------------

alter table public.players enable row level security;
alter table public.scores  enable row level security;

-- Önceden (elle) eklenmiş policy varsa temizle.
do $$
declare
  r record;
begin
  for r in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public' and tablename in ('players', 'scores')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end
$$;

-- Supabase yeni tablolara varsayılan olarak anon/authenticated yetkisi
-- verir; hepsini geri al.
revoke all on table    public.players        from public, anon, authenticated;
revoke all on table    public.scores         from public, anon, authenticated;
revoke all on sequence public.scores_id_seq  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) register_player(p_instagram, p_full_name) → uuid
--    Kullanıcı adı: boşlukları ve baştaki @ işaretini temizler, küçük harfe
--    çevirir, formatı doğrular. Ad soyad: kontrol karakterlerini atar,
--    boşlukları tekler, baş ve sondaki boşlukları kırpar; 2-40 karakter.
--    Aynı kullanıcı adı tekrar gelirse ad soyad güncellenir, aynı id döner.
--    İstemci bu fonksiyonu sadece KVKK onayı işaretlendikten sonra çağırır.
-- ---------------------------------------------------------------------

create or replace function public.register_player(
  p_instagram text,
  p_full_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kullanici text;
  v_ad_soyad  text;
  v_id        uuid;
begin
  v_ad_soyad := regexp_replace(coalesce(p_full_name, ''), '[[:cntrl:]]', '', 'g');
  v_ad_soyad := btrim(regexp_replace(v_ad_soyad, '\s+', ' ', 'g'));
  if char_length(v_ad_soyad) < 2 or char_length(v_ad_soyad) > 40 then
    raise exception 'gecersiz_isim' using errcode = 'P0001';
  end if;

  v_kullanici := lower(regexp_replace(coalesce(p_instagram, ''), '\s', '', 'g'));
  v_kullanici := regexp_replace(v_kullanici, '^@+', '');
  if v_kullanici !~ '^[a-z0-9._]{1,30}$' then
    raise exception 'gecersiz_instagram' using errcode = 'P0001';
  end if;

  -- Ekle; kullanıcı adı varsa ad soyadı güncelle ve aynı id'yi döndür
  -- (tek ifade, eşzamanlı isteklerde de güvenli).
  insert into public.players (instagram, full_name, kvkk_consent)
  values (v_kullanici, v_ad_soyad, true)
  on conflict (instagram) do update
    set full_name = excluded.full_name
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) submit_score(p_player, p_score) → void
--    Skor 0–300 aralığında olmalı; aynı oyuncu 3 saniyede en fazla
--    1 skor gönderebilir. Kontrol tek bir atomik UPDATE ile yapılır,
--    eşzamanlı isteklerde de kural delinmez.
-- ---------------------------------------------------------------------

create or replace function public.submit_score(
  p_player uuid,
  p_score  int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_score is null or p_score < 0 or p_score > 300 then
    raise exception 'gecersiz_skor' using errcode = 'P0001';
  end if;

  -- Son gönderimden 3 sn geçtiyse zaman damgasını güncelle (satır kilitlenir).
  update public.players
     set last_score_at = clock_timestamp()
   where id = p_player
     and (last_score_at is null
          or last_score_at <= clock_timestamp() - interval '3 seconds')
  returning id into v_id;

  if v_id is null then
    if not exists (select 1 from public.players where id = p_player) then
      raise exception 'oyuncu_bulunamadi' using errcode = 'P0001';
    end if;
    raise exception 'cok_sik_gonderim' using errcode = 'P0001';
  end if;

  insert into public.scores (player_id, score) values (p_player, p_score);
end;
$$;

-- ---------------------------------------------------------------------
-- 5) leaderboard(p_limit) → table(name, best)
--    Her oyuncunun en iyi skoru; eşitlikte o skora önce ulaşan üstte.
--    name sütunu "@kullaniciadi" biçimindedir.
--    p_limit 1–50 arasına sıkıştırılır.
-- ---------------------------------------------------------------------

create or replace function public.leaderboard(
  p_limit int default 10
)
returns table (name text, best int)
language sql
stable
security definer
set search_path = public
as $$
  with best_per_player as (
    -- Oyuncu başına en yüksek skor ve o skora ilk ulaşma zamanı.
    select distinct on (s.player_id)
           s.player_id, s.score, s.created_at
    from public.scores s
    order by s.player_id, s.score desc, s.created_at asc
  )
  select '@' || p.instagram as name,
         b.score            as best
  from best_per_player b
  join public.players p on p.id = b.player_id
  order by b.score desc, b.created_at asc
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$$;

-- ---------------------------------------------------------------------
-- 6) player_rank(p_player) → table(rank, total, best)
--    Oyuncunun en iyi skoruna göre sırası, skoru olan toplam oyuncu sayısı
--    ve oyuncunun en iyi skoru. Sıralama leaderboard ile aynıdır (eşitlikte
--    önce ulaşan üstte). Oyuncunun henüz skoru yoksa rank ve best null döner.
--    Dönüş tipi değiştiğinde create or replace yetmez; önce drop edilir.
-- ---------------------------------------------------------------------

drop function if exists public.player_rank(uuid);

create function public.player_rank(
  p_player uuid
)
returns table (rank int, total int, best int)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.players where id = p_player) then
    raise exception 'oyuncu_bulunamadi' using errcode = 'P0001';
  end if;

  return query
  with best_per_player as (
    select distinct on (s.player_id)
           s.player_id, s.score, s.created_at
    from public.scores s
    order by s.player_id, s.score desc, s.created_at asc
  ),
  me as (
    select b.score, b.created_at
    from best_per_player b
    where b.player_id = p_player
  )
  select
    -- Önündeki oyuncu sayısı + 1; skoru yoksa null.
    case when exists (select 1 from me) then
      (select 1 + count(*)::int
         from best_per_player b, me
        where b.score > me.score
           or (b.score = me.score and b.created_at < me.created_at))
    end,
    (select count(*)::int from best_per_player),
    (select me.score from me);
end;
$$;

-- ---------------------------------------------------------------------
-- 7) Fonksiyon yetkileri
--    Postgres fonksiyonlara varsayılan olarak PUBLIC'e, Supabase de
--    anon/authenticated'a execute verir. Hepsini geri alıp sadece
--    anon'a veriyoruz.
-- ---------------------------------------------------------------------

revoke all on function public.register_player(text, text) from public, anon, authenticated;
revoke all on function public.submit_score(uuid, int) from public, anon, authenticated;
revoke all on function public.leaderboard(int)        from public, anon, authenticated;
revoke all on function public.player_rank(uuid)       from public, anon, authenticated;

grant execute on function public.register_player(text, text) to anon;
grant execute on function public.submit_score(uuid, int) to anon;
grant execute on function public.leaderboard(int)        to anon;
grant execute on function public.player_rank(uuid)       to anon;

commit;

-- =====================================================================
-- Örnek yönetici sorguları (sadece SQL Editor'da, elle çalıştırın)
-- =====================================================================

-- Kazananları Instagram kullanıcı adı ve ad soyadla listele (ilk 3; eşitlikte önce ulaşan üstte).
-- Ad soyad sadece ödülü verirken kişiyi doğrulamak içindir; paylaşmayın.
--
-- select '@' || p.instagram as instagram, p.full_name, b.score as best, b.created_at as ulasma_zamani
-- from (
--   select distinct on (player_id) player_id, score, created_at
--   from public.scores
--   order by player_id, score desc, created_at asc
-- ) b
-- join public.players p on p.id = b.player_id
-- order by b.score desc, b.created_at asc
-- limit 3;

-- Etkinlik sonrası veri silme sorgusu ayrı dosyadadır: temizlik.sql
