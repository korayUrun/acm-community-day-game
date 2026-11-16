# Debug Ördeği – MSKÜ ACM Community Day Oyunu

MSKÜ ACM Student Chapter'ın tanıtım standı için, ziyaretçilerin QR kod okutup kendi telefonlarında oynadığı Flappy tarzı özgün bir mobil oyun. Skorlar Supabase'de tutulur, standdaki büyük ekranda canlı skor tablosu gösterilir. Oyunun ikinci amacı ACM'nin tanıtımı ve üye kaydı.

## Proje yapısı

```
/
├── CLAUDE.md
├── supabase.sql      # Tablolar, RLS ve RPC fonksiyonları (SQL Editor'da elle çalıştırılır)
├── temizlik.sql      # Etkinlik sonrası TÜM verileri siler (KVKK, 2 gün içinde). Etkinlik bitmeden çalıştırma.
└── yayin/            # Netlify Drop'a sürüklenen klasör; sadece bu üçü yayınlanır
    ├── index.html    # Telefonda oynanan oyun (kayıt → oyun → oyun bitti)
    ├── scoreboard.html  # Standdaki TV/laptop için yatay, tam ekran skor tablosu + QR
    └── logo.svg      # MSKÜ ACM logosu (tek dış görsel)
```

- Build adımı, framework ve npm yok. Her HTML dosyası tek başına çalışır: CSS ve JS dosyanın içinde.
- Dış kütüphaneler sadece jsDelivr/cdnjs'ten, **sabit sürümle** yüklenir (ör. `@supabase/supabase-js@2.x.y`). `@latest` kullanma.
- Yayın: Netlify Drop (`yayin/` klasörünü sürükle-bırak). SQL dosyaları yayınlanmaz. Sunucu tarafı kod yok; tüm arka uç Supabase.

## Yapılandırma

Her HTML dosyasının en üstünde, doldurulacak sabitler tek bir blokta durur:

```js
const SUPABASE_URL = "";
const SUPABASE_ANON_KEY = "";   // anon / publishable anahtar – herkese açık olabilir
const OYUN_URL = "";            // scoreboard.html'deki QR kod için
const LINKTREE_URL = "";        // "MSKÜ ACM'ye katıl" butonu ve reklam bandı
const INSTAGRAM_HESABI = "";    // "@" olmadan (ör. "mskuacm"); takip kuralı, "Instagram'da takip et" butonu, reklam bandı
const ODUL_METNI = "";          // ödül metni; takip kuralını da içerir
const KVKK_EPOSTA = "";         // aydınlatma metnindeki iletişim adresi; boşsa "[E-POSTA]" görünür
```

Yeni bir ayar gerekirse buraya ekle; kodun içine sabit değer gömme.

## Güvenlik kuralları (pazarlık yok)

1. **service_role / secret anahtarı hiçbir dosyaya, yoruma veya örneğe girmez.** Sadece anon/publishable anahtar kullanılır.
2. **Tablolara tarayıcıdan doğrudan erişim yok.** `supabase.from(...)` kullanma. Tüm işlemler `supabase.rpc(...)` ile şu 4 fonksiyon üzerinden yapılır:
   - `register_player(p_instagram text, p_full_name text) → uuid` — kullanıcı adı: boşlukları ve baştaki `@` işaretini temizler, küçük harfe çevirir; 1–30 karakter, sadece `a-z 0-9 . _`. Ad soyad: boşlukları tekler ve kırpar; 2–40 karakter. Aynı kullanıcı adı tekrar gelirse ad soyad güncellenir, aynı id döner. İstemci bunu sadece KVKK onayı işaretlendikten sonra çağırır.
   - `submit_score(p_player uuid, p_score int) → void`
   - `leaderboard(p_limit int default 10) → table(name text, best int)` — `name` "@kullaniciadi" biçimindedir; `p_limit` 1–50 arasına sıkıştırılır.
   - `player_rank(p_player uuid) → table(rank int, total int, best int)` — oyuncunun en iyi skoruna göre sırası, skoru olan toplam oyuncu sayısı ve en iyi skoru; sıralama `leaderboard` ile aynı (eşitlikte o skora önce ulaşan üstte). Oyuncunun henüz skoru yoksa `rank` ve `best` null döner. Dönüş tipi değişirse `create or replace` yetmez: `supabase.sql`'de önce `drop function if exists`, sonra `create`.
3. `players` ve `scores` tablolarında RLS açık ve **hiç policy yok**. anon/authenticated rollerinin tablolarda yetkisi yok. Fonksiyonlar `security definer` + `set search_path = public`; `execute` izni sadece bu 4 fonksiyona ve sadece anon'a verilir.
4. **Instagram kullanıcı adı sadece skor tablosunda ve oyun bitti ekranında görünür; console'a yazılmaz.**
   **Ad soyad hiçbir ekranda gösterilmez, console'a ve localStorage'a yazılmaz, hiçbir RPC çıktısında yer almaz;** sadece ödül verirken kişiyi doğrulamak için veritabanında tutulur. Tek istisna: oyuncunun kendi cihazındaki "Hazır mısın, Ali?" selamlaması için ilk isim localStorage'da tutulur.
   localStorage'da sadece `player_id` (uuid), kullanıcı adı, ilk isim, kişisel rekor, ses ayarı ve seçili karakter tutulur.
5. Skor sunucuda doğrulanır: 0–300 aralığı ve aynı oyuncudan 3 saniyede en fazla 1 skor. İstemciye güvenme.
6. Skor tablosunda oyuncu "@kullaniciadi" olarak gösterilir.
7. Kullanıcıdan gelen metni DOM'a `textContent` ile yaz, `innerHTML` ile değil.

## KVKK

- Kayıt formunda iki alan ("Ad Soyad" ve "Instagram kullanıcı adın") ve zorunlu "Aydınlatma metnini okudum" onayı bulunur (`players.kvkk_consent` true olmak zorunda).
- Toplanan veri: ad soyad, Instagram kullanıcı adı, skor. Amaç: ad soyad yalnızca ödül verirken kimlik doğrulama; kullanıcı adı skor tablosunda gösterilmek ve kazananları Instagram'da etiketlemek. Aydınlatma metni en fazla 3 cümledir. Saklama süresi: etkinlikten 2 gün sonra silinir. Veriler Supabase'de (yurt dışı sunucu) tutulur. Aydınlatma metni `index.html`'deki kayıt ekranındadır; bu bilgiler değişirse orayı da güncelle.
- Formda yeni bir alan (e-posta, bölüm vb.) ekleme. Gerekirse önce sor; aydınlatma metni de güncellenmeli.

## Oyun ve marka

- **Özgün oyun:** "Flappy Bird" adı, görselleri veya sesleri kullanılmaz. Ana karakter jetpack'li sarı bir lastik ördek (rubber duck debugging'e gönderme), kafasında pilot gözlüğü; engeller kod parantezlerine benzeyen `{ }` sütunlar. Tüm görseller canvas ile kodla çizilir; tek dış görsel `logo.svg`'dir (MSKÜ ACM logosu); yayın klasörüne de eklenmelidir. Logo yüklenemezse oyun logosuz çalışmaya devam eder.
- Logonun kullanımı: kayıt ekranı, oyun bitti ekranı ve scoreboard başlığında logo **doğrudan koyu zeminde, tek renk beyaz** gösterilir (CSS `filter: brightness(0) invert(1)`, opaklık %95); arkasında beyaz kutu yok, etrafında padding ile boşluk var. Sadece zeplinin beyaz gövdesindeki kopya orijinal renkleriyle çizilir. Logo yüklenemezse bu alanlar gizli kalır ve yer kaplamaz (düzen bozulmaz).
- Mekanik: Dokununca zıpla, her geçilen sütun 1 puan, zorluk yavaşça artar. Telefonlarda 60 fps akıcı olmalı.
- Animasyonlar (tüm karakterlerde): dokununca jetpack alevi + duman ve squash & stretch; hıza göre eğilme; ara sıra göz kırpma; çarpınca ekran sallantısı ve dönerek düşme (ördekte tüy, kedide küçük kalpler, hamamböceğinde küçük yıldızlar saçılır); her 10 puanda parlama + ses. Parçacıklar sabit boyutlu bir havuzdan gelir (en fazla 64), her karede yeni nesne üretilmez.
- Karakterler: kilit/puanla açma sistemi yok; 3 karakter baştan seçilebilir, hepsi jetpack'li ve aynı sevimli, yuvarlak hatlı (chibi) tarzda: "Ördek" (varsayılan; jetpack'li sarı lastik ördek), "Kedi" (turuncu tekir, büyük parlak gözler, pembe burun; kuyruğu uçarken sallanır, ara sıra kulağını oynatır), "Hamamböceği" (tamamen özgün tasarım: kahverengi, yuvarlak, iri gözlü, kaşları çatık ama sevimli; uzun antenleri uçarken salınır; başında ACM mavisi kulaklık; hiçbir meme'e veya bilinen karaktere benzemez). Ekranda isimler bu şekilde, önizlemelerin altında yazar. Çarpışma kutusu herkes için aynıdır (`karakter.r`'ye bağlı daire), görünüm zorluğu değiştirmez. Seçim "Hazır mısın" ekranında animasyonlu önizlemelerle yapılır (oyun bitti ekranındaki "Karakter değiştir" de oraya götürür) ve localStorage'da hatırlanır. "Hazır mısın" ekranının en altında küçük, göze batmayan "Farklı bir hesapla oyna" bağlantısı vardır: kaydı (id, kullanıcı adı, ilk isim, rekor) siler ve kayıt ekranına döner; karakter seçimi ve ses ayarı kalır.
- Ses efektleri WebAudio ile üretilir, kullanıcı etkileşiminden sonra başlar ve sessize alınabilir.
- Tema koyu, ACM mavisi ağırlıklı. Butonlar büyük ve tek elle dokunulabilir. Arayüz metinleri Türkçe.

### ACM tanıtım içeriği (oyunun içinde)

- Her 5 sütunda bir, sütun üstünde küçük ACM tabelası.
- Arka planda yavaşça geçen beyaz zeplin (aynı anda tek zeplin; önceki ekrandan tamamen çıktıktan sonra 15-20 saniye beklenir): gövdesinde logo.svg (orijinal renkler; yüklenemezse "MSKÜ ACM" yazısı), arkasında "23 Ekim · Teknopark İzmir" afişi. Logo arka plana filigran olarak konmaz.
- Oyun bitti ekranı: skor, kişisel rekor, ilk 10 ve kişinin sırası ("X kişi arasında Y. sıradasın"); tek bir "MSKÜ ACM'ye katıl" butonu (LINKTREE_URL) ve hemen altında "Instagram'da takip et" butonu (`https://www.instagram.com/INSTAGRAM_HESABI`, yeni sekme), "23 Ekim'de Teknopark İzmir'in davetiyle teknik gezideyiz", ödül (ODUL_METNI), büyük "Tekrar oyna" butonu ve altında küçük "Karakter değiştir" ve "🏆 Skor tablosu" bağlantıları. Başka buton/bağlantı yok ("Ben değilim" burada bulunmaz).
- Telefondaki skor listesi (oyun bitti ekranı ve "🏆 Skor Tablosu" paneli aynı yapıyı kullanır): `leaderboard(10)`. Oyuncu ilk 10'daysa kendi satırı ACM mavisiyle vurgulanır ve yanında "Sen" etiketi vardır; değilse listenin altına "···" ayırıcısı ve ardından vurgulu kendi satırı gelir ("87. @kullaniciadi – 12"); sıra ve skor `player_rank`'ten (`rank`, `best`) gelir. Kendi satırı **kullanıcı adıyla** bulunur ("@" + localStorage'daki kullanıcı adı); ad soyad kullanılmaz.
- "🏆 Skor Tablosu" paneli: "Hazır mısın" ekranındaki butondan ve oyun bitti ekranındaki bağlantıdan açılır, tam ekran. Açıkken 5 saniyede bir yenilenir; kapanınca yenileme durur. Oyun sırasında asla çalışmaz (panel sadece hazır/oyun bitti ekranlarından açılabilir).
- Ödül kuralı: ödül kazanmak için MSKÜ ACM'nin Instagram hesabını (INSTAGRAM_HESABI) takip etmek gerekir. Kayıt ekranında kullanıcı adı alanının altındaki açıklamada "Ödül kazanmak için @hesap'yi takip etmelisin." yazar (buton yok, sadece kural yazısı). Hesap adı INSTAGRAM_HESABI'dan gelir; Türkçe ek ("'yi") sabittir, otomatik ek üretilmez. ODUL_METNI de bu kuralı içerir.
- Gerçek dışı iddia yazma (ör. topluluğun yapmadığı etkinlikler, sahte üye sayısı). Emin olmadığın bilgiyi sabit olarak bırak, uydurma.

## scoreboard.html

- Yatay, tam ekran, 3 metreden okunur büyüklükte yazılar.
- `leaderboard` RPC'si her 4 saniyede bir çağrılır (Realtime kullanılmaz; tablolar zaten dışarıya kapalı).
- Sıra değişince satır parlar ve kısa bir ses çalar (ekranda "Sesi aç" butonu).
- 1. sıradaki kişi değişince 3 saniyelik tam ekran kutlama: "👑 YENİ LİDER", @kullaniciadi ve skoru, canvas konfeti ve fanfar sesi. Sayfa ilk açıldığında çıkmaz, sadece gerçek bir lider değişiminde çıkar.
- Sağda OYUN_URL için büyük QR kod ve "Telefonunla okut, oyna, kazan!" başlığı; altta dönen ACM reklam bandı (katılım için LINKTREE_URL ve "Ödül için Instagram'da @hesap'yi takip et!" satırı gösterilir). Geri sayım / bitiş saati yok.
- İnternet kesilirse son liste ekranda kalır, köşede "bağlantı bekleniyor" uyarısı çıkar.

## Hata durumları

- Supabase'e ulaşılamazsa oyun yine oynanabilir; skor gönderilemediğinde anlaşılır Türkçe mesaj göster ve tekrar denemeyi teklif et.
- RPC fonksiyonları hata durumunda kısa bir kod fırlatır (`error.message` içinde gelir). `index.html` bu kodları şöyle Türkçeye çevirir; ham kodu kullanıcıya gösterme:

  | Kod | Fırlatan | İstemcide |
  |---|---|---|
  | `gecersiz_isim` | `register_player` | "Adını ve soyadını yaz (2-40 karakter)." |
  | `gecersiz_instagram` | `register_player` | "Geçerli bir Instagram kullanıcı adı gir (harf, rakam, nokta ve alt çizgi)." |
  | `gecersiz_skor` | `submit_score` | "Skor kaydedilemedi, tekrar dene" |
  | `cok_sik_gonderim` | `submit_score` | "Skor kaydedilemedi, tekrar dene" |
  | `oyuncu_bulunamadi` | `submit_score`, `player_rank` | Mesaj yok: localStorage'daki kaydı sil, kayıt ekranına dön |

  Bilinmeyen hata veya ağ hatası: "Skor kaydedilemedi, tekrar dene" + tekrar deneme.
- `permission denied` hatası alınırsa sebep büyük ihtimalle eksik `grant execute`'tur; önce `supabase.sql`'i kontrol et, istemci tarafında tabloya erişim ekleyerek "çözme".

## Değişiklik yaparken

- Mevcut yapıyı koru: tek dosya, framework yok, build yok.
- `supabase.sql` değişirse, değişikliğin tekrar çalıştırılabilir olmasına dikkat et (`create or replace`, `if not exists`) ve dosyanın başına kısa bir değişiklik notu yaz.
- Her değişiklikten sonra kontrol listesi:
  - [ ] Dosyalarda service_role anahtarı yok
  - [ ] `.from(` kullanımı yok, sadece `.rpc(`
  - [ ] Instagram kullanıcı adı console'a yazılmıyor; sadece skor tablosunda ve oyun bitti ekranında görünüyor
  - [ ] Ad soyad hiçbir ekranda, console'da, localStorage'da ve RPC çıktısında yok
  - [ ] iPhone Safari ve Android Chrome'da dokunmatik çalışıyor; çift dokunma ile yakınlaştırma ve sayfa kaydırma yok
  - [ ] İnternet kapalıyken oyun açılıyor ve çökmüyor