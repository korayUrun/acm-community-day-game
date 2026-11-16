-- =====================================================================
-- !!! BU DOSYA TÜM VERİLERİ SİLER, ETKİNLİK BİTMEDEN ÇALIŞTIRMA !!!
-- =====================================================================
--
-- Debug Ördeği – etkinlik sonrası veri temizliği (KVKK).
-- Tüm oyuncuları (Instagram kullanıcı adı, KVKK onayı) ve skorları kalıcı olarak
-- siler. GERİ ALINAMAZ.
--
-- Ne zaman: kazananlarla iletişim tamamlandıktan sonra, etkinlikten
-- 2 gün sonra (aydınlatma metninde verilen süre).
-- Nasıl: Supabase panelinde SQL Editor'a yapıştırıp çalıştırın.
-- Tablolar ve fonksiyonlar kalır; sadece içlerindeki veri silinir.
-- =====================================================================

-- Tüm skorları ve oyuncuları sil.
truncate table public.scores, public.players;

-- Kontrol: iki sayı da 0 olmalı.
select
  (select count(*) from public.players) as oyuncu_sayisi,
  (select count(*) from public.scores)  as skor_sayisi;
