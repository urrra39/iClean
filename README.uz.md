# iClear (avvalgi nomi iClean)

[![CI](https://github.com/urrra39/iClear/actions/workflows/ci.yml/badge.svg)](https://github.com/urrra39/iClear/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **1.0.0 versiyasi (2026-10-02).** Bitta Mac'da (Apple M3 Pro, 18 GB, macOS 27.0.1) laboratoriya ishga
> tushirgan haqiqiy ilovalar (Chrome, VS Code, TextEdit, Preview) va simulyatorlar bilan
> tasdiqlangan, hech qachon shaxsiy akkauntlar bilan emas. 7 kunlik uzoq sinov (soak)
> 2026-10-01 20:29 UTC dan beri davom etmoqda; natijalari ma'lumot yig'ilgach e'lon qilinadi.
> iClear **Kuzatish rejimida** boshlanadi, u faqat nima qilgan bo'lardi, shuni yozib
> boradi. Avvalgi nomi iClean; "iClean dan o'tish" bo'limiga qarang.

iClear xotirasi tugayotgan Mac'da fonda bo'sh turgan ilovalarni pauza qiladi va siz
qaysi biriga qaytsangiz, uni o'sha zahoti davom ettiradi. Pauza qilingan ilova
oynalari, tablari va saqlanmagan holatini saqlab qoladi. U shunchaki ishlashdan
to'xtaydi, shunda macOS u bilan RAM uchun kurashish o'rniga uning xotirasini siqishi
yoki svopga chiqarishi mumkin. Xotira bosimi me'yorida bo'lsa, iClear hech narsa
qilmaydi.

**iClear hech qachon fayllaringizni o'chirmaydi.** U faqat pauza qiladi, davom ettiradi
va maslahat beradi. Kesh, log yoki yuklanmalarni o'chirmaydi. Apple Inc. bilan bog'liq
emas va shunga o'xshash nomli tozalagich ilovalar bilan aloqasi yo'q
([NAMING.md](docs/NAMING.md)).

[English](README.md) · [Qanday ishlaydi](docs/ARCHITECTURE.md) · [Xavfsizlik](docs/SAFETY.md) ·
[Tasdiqlash natijalari](docs/VALIDATION.md) · [Savol-javob](docs/FAQ.md) (hujjatlar ingliz tilida)

<p align="center"><img src="docs/images/menu-uz.png" width="360" alt="iClear menyusi: Mac salomatligi 100/100, xotira me'yorida, Kuzatish rejimi"></p>

## Tasdiqlangan doira

| Tasdiqlangan (laboratoriya, bitta Mac) | Natija |
|---|---|
| Haqiqiy ilovalarni (Chrome, VS Code, TextEdit, Preview) pauza qilish va davom ettirish: har biriga 300 sikl, 100 tasi 8 GB sun'iy bosim ostida | 0 qotish, 0 pauzada qolgan, 0 hujjat o'zgarishi, 0 crash hisobot; 15.1 ms ichida yana javob beradi (p99) |
| Ilovalar pauzada (100 marta) yoki stash'da (50 marta) turganda xizmat `kill -9` bilan o'chirildi | 150/150 holatda 2 soniya ichida davom ettirildi va ko'rsatildi; p99 98 ms |
| Stash va pop, 4 ilovaning 50 sikli | oynalar 0.0 nuqta aniqlikda joyida (350/350); oldingi faol ilova 50/50 holatda qaytdi; pauzada yoki yashirin qolgan yo'q |
| Pleyer ijro etganda, qo'ng'iroq mikrofondan foydalanganda yoki Chrome yuklab olganda himoyalar | 123 ta muzlatish urinishining 123 tasi rad etildi |
| 10-300 soniyalik pauzalar: Chrome tablari, chat mijozlari | ma'lumot yo'qolmadi; Chrome va heartbeat'li chat mijozi taxminan 1.1 soniyada tiklandi; heartbeat'siz mijoz oflayn qoldi (shuning uchun chat ilovalari himoyalangan) |
| Barcha imkoniyatlar yoqilgan 60 daqiqalik sinov, Faol laboratoriya xizmati | 60 daqiqa, 0 xato: 12/12 stash/pop sikli, 6 bosim epizodi, 6/6 simulyatsiya qilingan qo'ng'iroq aniqlandi, 0 qotish |
| Xizmat yuki, 10 daqiqa, haqiqiy ilovalar, Kuzatish rejimi | protsessorning bitta yadrosidan 0.48%, 40 MB |
| `iclear selftest` (to'liq) | 13 ta tekshiruvdan 13 tasi o'tdi, o'tkazib yuborilgani yo'q |

**Tasdiqlanmagan:** haqiqiy Slack, Spotify yoki istalgan shaxsiy akkaunt (qo'lda
tekshirish ro'yxati [MANUAL_TESTS_APPS.md](docs/MANUAL_TESTS_APPS.md) da); Intel Mac'lar
(u yerda faqat CI testlari ishlaydi); macOS 13 va 14; 8 GB va undan kam xotirali Mac'lar;
batareya taxminlari (batareyadan ishlagan holda yaroqli sinovlar yo'q; maqsad rejimi
tajribaviy va o'chirilgan); 7 kunlik soak (davom etmoqda); Safari, Docker, Xcode va
virtual mashinalarni muzlatish; saqlanmagan o'zgarishlar signali (laboratoriyada hech bir ilova uni bermadi); pauzadagi pleyerga yuborilgan media tugmalari; issiqlik himoyasi. Testi yo'q hamma narsa
[TEST_MATRIX.md](docs/TEST_MATRIX.md) da sanab o'tilgan.

## Qachon yordam beradi va qachon bermaydi

**Yordam beradi:** xotira bosimi sariq yoki qizil, siz ishlatmayotgan bir nechta og'ir
ilova ochiq (brauzerlar, Electron ilovalari, dizayn vositalari, muharrirlar) va ular
fonda tez-tez uyg'onib turadi.

**Yordam bermaydi:**

- Xotira bosimi yashil. macOS buni o'zi yaxshi uddalaydi va iClear hech narsa qilmaydi.
- Xotirani siz hozir ishlayotgan ilova egallagan.
- Xotira to'xtamasligi kerak bo'lgan narsaga tegishli (build, model, virtual mashina,
  qo'ng'iroq). iClear ularni pauza qilmaydi.
- Uyg'onmasdan jim turgan ilovalar. macOS ularni baribir siqadi, muzlatilgan yoki
  muzlatilmaganidan qat'i nazar.
- Kundalik ishingiz uchun RAM shunchaki yetmaydi. Bir haftalik ma'lumot yig'ilgach,
  `iclear advise` buni aytib beradi.

## Nima qiladi

| Imkoniyat | Sukut bo'yicha | Izoh |
|---|---|---|
| Xotira bosimi ostida bo'sh fon ilovalarini pauza qilish va davom ettirish | `iclear mode active` gacha Kuzatish rejimi (faqat yozib boradi) | Butun jarayonlar daraxti, ko'rinadigan oyna yo'q, barcha tekshiruvlardan o'tgan; ilova faollashtirilganda birinchi bo'lib davom ettiriladi |
| Ish stolini yig'ib qo'yish (Stash): `iclear stash <nom>`, `iclear pop` | siz so'raganingizda | Bir nechta ilovani yashirib pauza qiladi va xuddi o'sha oynalar va oldingi faol ilova bilan qaytaradi; audio, mikrofon, quvvat tasdig'i (power assertion) yoki kamerada qo'ng'iroq qilayotgan ilovalarni hech qachon pauza qilmaydi |
| Ilova sinflari, `iclear compat <ilova>` | yoqilgan | Chat, pochta, taqvim va media ilovalari sukut bo'yicha hech qachon pauza qilinmaydi; audio ijro etayotgan yoki mikrofondan foydalanayotgan ilova, undan keyin ham 10 daqiqa davomida pauza qilinmaydi; brauzerlar ikki baravar uzoqroq kutadi |
| `iclear why`, Mac salomatligi bahosi, runaway himoyasi | yoqilgan | O'lchangan ma'lumotdan oddiy tildagi javoblar; runaway himoyasi faqat xabar beradi |
| `iclear selftest` | yoqilgan | Mac'ingizda iClear'ning o'z sinov jarayonlari bilan taxminan 2 daqiqalik tekshiruv |
| `iclear before <ilova>` | yoqilgan | "Buni ochsam xotira sariqqa o'tadimi?" Mac'ingiz tarixidan; 30 tadan kam o'lchov bo'lsa javob bermaydi |
| Beachball tahlili: `iclear beachball` | yoqilgan, Accessibility kerak | Oldingi ilova qotib qolishlarini va o'sha paytda Mac nima qilayotganini yozadi |
| Batareya taxminlari: `iclear battery` | taxminlar "taxmin" belgisi bilan ko'rsatiladi; **maqsad rejimi tajribaviy va o'chirilgan** | Tasdiqlanmagan |
| Qo'ng'iroq rejimi (Call Mode), Beachball yumshatish, issiqlik himoyasi | **o'chirilgan** | Yoqish qoidalari [RELEASE_CRITERIA.md](docs/RELEASE_CRITERIA.md) da (C8); laboratoriyada Qo'ng'iroq rejimi taymer tebranishini kamaytirdi, lekin boshqa ilovalar ishini ikki baravar kamaytirdi, Beachball yumshatish esa natijani biroz yomonlashtirdi ([VALIDATION.md](docs/VALIDATION.md)) |
| Profillar, Fokus xavfsiz rejimi, Bekor qilish, Hammasini davom ettirish, favqulodda tugmalar (menyu ilovasi ishlaganda Control-Option-Command-T), hisobot, explain | yoqilgan | 0.1 dagidek |

Har birining holati va dalillari: [SIGNATURE_FEATURES.md](docs/SIGNATURE_FEATURES.md).

## Ma'lum yon ta'sirlar

Pauza ilovaga nima qilishi simulyatorlar va mahalliy sahifalardagi Chrome bilan
o'lchangan ([VALIDATION.md](docs/VALIDATION.md), "Side effects"). Yuqoridagi sukut
sozlamalari shular sababli bor; `iclear compat <ilova>` ularni bitta ilova uchun
ko'rsatadi.

- **Chat, pochta va taqvim ilovalari** siz o'zingiz yoqmaguningizcha hech qachon pauza
  qilinmaydi. Pauzadagi ilova hech narsa qabul qilmaydi, u javob bermay qo'ygach esa
  server ulanishni uzadi (laboratoriya serveri 30 soniyadan keyin). O'z "yurak urishi"
  (heartbeat) tekshiruvi bor simulyatsiya qilingan mijoz davom ettirilgandan keyin
  taxminan 1.1 soniyada qayta ulandi va o'tkazib yuborilgan barcha xabarlarni kechikib
  (300 soniyalik pauzadan keyin 296 soniyagacha) oldi, birortasi ham yo'qolmadi. Uzilishni
  faqat soketdan bilishga tayanadigan mijoz 60 soniya va undan uzun har bir pauzadan
  keyin **oflayn qolib ketdi**. Ixtiyoriy "uyg'onish oynalari"
  (`packaging/rules/chat-wake-windows.json`) laboratoriyada eng katta kechikishni 296
  soniyadan 36 soniyaga qisqartirdi, evaziga ilova tez-tez uyg'onadi; qo'ng'iroq paytida
  ular qayta muzlatilmaydi.
- **Media pleyerlar** sukut bo'yicha hech qachon pauza qilinmaydi: ijro paytida ham,
  undan keyingi 10 daqiqada ham. Pauzadagi pleyer media tugmalari yoki Boshqaruv
  markaziga javob bera olmaydi; bunda macOS nima qilishi qo'lda tekshiriladi.
- **Brauzerlar** faqat butun daraxt sifatida va hech bir tab audio ijro etmayotgan,
  mikrofon yoki kameradan foydalanmayotgan, yuklab olmayotgan, fayl yozmayotgan va quvvat
  tasdig'ini ushlab turmagan paytda pauza qilinadi (WebRTC ulanishi ochiq turganda Chrome
  shunday tasdiqni ushlab turadi). Laboratoriyada bu himoyalar sinov Chrome'ini pauza
  qilishga bo'lgan har bir urinishni rad etdi. Laboratoriya uni baribir 10-300 soniyaga
  pauza qilganda, har bir sahifa davom ettirilgandan keyin 0.03 soniya ichida javob berdi,
  formadagi ma'lumot va taymerlar saqlanib qoldi, WebSocket sahifalari 1.1 soniya ichida
  qayta ulandi, WebRTC ma'lumot kanali va service worker ishlashda davom etdi.
- **"Not Responding" (javob bermayapti)**: pauza paytida ilova Force Quit, Activity Monitor
  yoki Dock menyusida "Not Responding" bo'lib ko'rinishi mumkin. Pauzadagi jarayon shunday
  ko'rinadi; uni faollashtirsangiz davom etadi. Uni majburan yopmang.
- **Soat va taymerlar**: pauza paytida vaqt o'tishda davom etadi. Davom ettirilgandan
  keyin takrorlanuvchi taymer bir marta ishlaydi (bir yo'la ko'p marta emas), pauzani qamrab
  olgan kutish muddatlari esa darhol tugaydi.
- **Uzilgan ulanishlar**: serverlar o'zlariga javob bermay qo'ygan ulanishlarni yopadi;
  qayta tiklanish ilovaning o'ziga bog'liq (ko'pchilik chat ilovalari qayta ulanadi,
  yuqoriga qarang). Yuklab olishlar himoyalangan: 200 MB yuklab olish to'g'ri nazorat
  yig'indisi (checksum) bilan tugadi, pauza qilishga bo'lgan har bir urinish esa rad etildi.
- Pauza paytiga to'g'ri kelgan **bildirishnomalar** kechikib chiqadi yoki umuman chiqmaydi
  (o'lchanmagan).

## O'lchangan natijalar

| Nima (bitta Mac, laboratoriya, tafsilotlar [VALIDATION.md](docs/VALIDATION.md) da) | Natija |
|---|---|
| Davom ettirishdan javob berishgacha (asosiy oqim Accessibility so'roviga javob beradi), haqiqiy ilovalarning 1 200 sikli | p50 2.5-3.6 ms, p99 ≤ 15.1 ms, maksimum 47.3 ms |
| "Sariq" (warning) bosimda muzlatilgan haqiqiy ilovalar qaytargan xotira (birinchi epizod) | Chrome 1 203 → 803 MB (−33%), VS Code 1 709 → 1 046 MB (−39%), Preview 130 → 84 MB (−35%); "me'yoriy" bosimda macOS kam qaytaradi (mediana −1% dan −4% gacha) |
| Xizmat `kill -9` bilan o'chirilgandan keyin davom ettirish (watchdog), 150 sinov | p50 76-85 ms, p99 98 ms |
| Pop: barcha yashirilgan ilovalar ko'ringuncha, 50 sikl | p50 1.34 s, p99 1.36 s (pop oldingi faol ilova 0.5 soniya oldinda turishini kutadi) |
| 24 ta raqobatchi jarayon ostida qo'ng'iroq taymeri tebranishi, Qo'ng'iroq rejimi o'chiq / yoqiq | p99 0.32 / 0.08 ms (Qo'ng'iroq rejimi o'chiq qoladi: u boshqa ilovalar ishini ikki baravar kamaytiradi) |
| Xizmat, bo'sh holatda, Kuzatish rejimi, haqiqiy ilovalar, 10 daqiqa | protsessorning bitta yadrosidan 0.48%, 40 MB |

Eski sintetik o'lchovlar: [BENCHMARKS.md](docs/BENCHMARKS.md).

## Ruxsatlar

| Ruxsat | Majburiymi? | Nima uchun | Rad etilsa |
|---|---|---|---|
| hech qanday | | pauza, davom ettirish, stash, `why`, salomatlik bahosi, himoyalar, qo'ng'iroqni aniqlash (iClear mikrofon yoki kamera *ishlatilayotganini* biladi, xolos; ovoz yoki tasvirni hech qachon olmaydi) | hammasi ishlaydi |
| Maxsus imkoniyatlar (Accessibility) | ixtiyoriy | davom ettirilgan ilova javob berishini tekshirish; kechikish; qotib qolish tahlili; stash'da "saqlanmagan o'zgarishlar"; pop'dan keyin aynan oldingi ilovani oldinga chiqarish | davom ettirishdan keyingi qotish aniqlanmaydi; kechikish va qotishlar "o'lchanmagan"; saqlanmagan holat "noma'lum" |
| Kiritishni kuzatish (Input Monitoring) | ixtiyoriy | tajribaviy oldindan davom ettirish (o'chirilgan) | hech narsa o'zgarmaydi |
| Mikrofon | faqat `iclear selftest` uchun | uning qo'ng'iroq tekshiruvi iClear'ning o'z sinov vositasini ishga tushiradi, u bir necha soniya yozib, darhol tashlab yuboradi | o'sha tekshiruv o'tkazib yuboriladi |
| Ekranni yozib olish, Kamera | ishlatilmaydi | | |

Root kerak emas, yadro kengaytmasi yo'q, SIP o'zgartirilmaydi, tarmoqqa ulanmaydi,
telemetriya yo'q.

## O'rnatish

macOS 13 va undan yangilari, Apple Silicon va Intel uchun qurilgan (universal ikkilik fayl).

[Oxirgi relizni](https://github.com/urrra39/iClear/releases) **yuklab oling**:
`iClear-<versiya>.zip` (menyu ilovasi; buyruq qatori vositalari
`iClear.app/Contents/Helpers` ichida) yoki `iclear-<versiya>-macos.tar.gz` (faqat buyruq
qatori vositalari). Tekshiring:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

Buildlar ad-hoc imzolangan, notarizatsiyadan o'tmagan. Ilovani birinchi marta ochish:
iClear.app ni o'ng tugma bilan bosing, Open ni tanlang va tasdiqlang. Buyruq qatori
vositalari: `xattr -dr com.apple.quarantine iclear-<versiya>`, keyin uning ichida `./iclear install`.

**Manba koddan:**

```sh
git clone https://github.com/urrra39/iClear.git && cd iClear
scripts/build-release.sh           # universal ikkilik fayllar, dist/iClear.app
cp -R dist/iClear.app /Applications/
```

Homebrew tap rejalashtirilgan, lekin hali chiqarilmagan; shablonlar
[`packaging/homebrew/`](packaging/homebrew/) da.

## Tez boshlash (60 soniya)

```sh
iclear selftest --quick # 12 soniyada pauza va davom ettirish shu Mac'da ishlashini tekshiradi
iclear install          # foydalanuvchi xizmatini Kuzatish rejimida ishga tushiradi
iclear status           # u nimani ko'rmoqda va nima qilgan bo'lardi
iclear why              # Mac nega hozir sekin?
iclear compat Chrome    # pauza ilovaga nima qilishi
# ...Mac'ingizdan bir kun foydalaning, keyin:
iclear stats --days 1   # u nima qilgan bo'lardi va taxminiy afsus darajasi
iclear mode active      # unga amal qilishga ruxsat bering
```

Ilova bilan: iClear ni Applications dan oching; "iClear'ni ishga tushirish" xizmatni
o'rnatadi. Favqulodda holat: **Control-Option-Command-T** yoki `iclear thaw --all`
hammasini davom ettiradi.

## Xavfsizlik modeli

Har bir pauzadan oldin muzlatish jurnali yoziladi, va xizmat ishdan chiqsa (hatto
`kill -9` bilan ham), alohida kuzatuvchi (watchdog) jarayon hammasini davom ettiradi
(laboratoriya: 100/100 tiklanish, p99 83 ms). Har bir signal oldidan PID, boshlanish
vaqti va egasi qayta tekshiriladi. Himoyalangan to'plamni (tizim, terminallar, AI
dasturlash agentlari, parol menejerlari, sinxronlash, VPN, kiritish va maxsus imkoniyat
vositalari) hech qanday qoida bilan pauza qilib bo'lmaydi. Daraxtlar "hammasi yoki hech
biri" tamoyili bilan pauza qilinadi. Pauza vaqti (4 soat) va umumiy hajmi (RAM ning 50%)
cheklangan. Ustuvorlik va yashirish o'zgarishlari jurnalga yoziladi va aynan qaytariladi.
Stash xizmatdan uzoq yashamaydi. Qo'ng'iroq rejimi, uni o'zingiz yoqsangiz, qo'ng'iroq
paytida harakat qiladigan yagona narsa, va qo'ng'iroqning o'ziga hech qachon tegmaydi
([SAFETY.md](docs/SAFETY.md)).

## Boshqalar bilan taqqoslash

Bu loyihalar o'xshash muammolarni hal qiladi va ularning bir nechtasi buni ilgariroq
qilgan. 2026-09-30 sanasida ularning README fayllarini o'qib chiqildi:

| Loyiha | Yondashuv | iClear dan farqi |
|---|---|---|
| [ForceNap](https://github.com/omikun/ForceNap) | Siz tanlagan ilovalarni fokusdan chiqqanda to'xtatadi, fokusga qaytganda davom ettiradi | Oddiy va to'g'ridan-to'g'ri. U tanlangan ilovalarni xotira bosimidan qat'i nazar to'xtatadi; iClear faqat bosim ostida harakat qiladi va ilovalarni o'zi tanlaydi |
| [Auto Pause Mac Apps](https://github.com/fazalrshah/auto-pause-mac-apps) | Ilovalarni pauza qilib RAM ni qaytarish uchun menyu ilovasi, holatni saqlab yopadigan "Deep Sleep" rejimi bilan | Qo'lda boshqarish qulay va iClear da yo'q holatni saqlab yopish rejimi bor. iClear avtomatik, bosimga asoslangan va himoyalar bilan tekshiriladi |
| [caproom](https://github.com/intelogroup/caproom) | Buyruqlar uchun xotira chegarasi; bo'sh jarayon daraxtlarini SIGSTOP bilan "to'xtatib qo'yadi", chegaradan oshsa o'chiradi | Terminal ishlari va agentlar uchun qat'iy chegaralar bilan qurilgan. iClear GUI ilovalarni nishonga oladi va hech qachon o'chirmaydi |
| [ProcessX](https://github.com/avantigroupai/ProcessX) | Jarayon/ustuvorlik monitori; protsessorni to'xtatib-davom ettirish orqali cheklaydi | Protsessor va ustuvorlikka qaratilgan. iClear xotira bosimiga qaratilgan |
| [GreenRAM](https://github.com/lwj1994/greenram) | RAM/svop chegarasidan oshganda uzoq bo'sh turgan fon ilovalarini majburan yopadi | Yopish barcha xotirani bo'shatadi, lekin holat yo'qoladi. iClear pauza qiladi va holatni saqlaydi |
| [Canaryd](https://github.com/ThaddeusJiang/canaryd) | To'xtab qolgan xizmatlar, Simulator, qizish va bo'sh xotira uchun kuzatuvchi; bo'sh og'ir ilovalardan yopilishni so'raydi | Dasturchi kompyuteri uchun kengroq kuzatuvchi. iClear yopish o'rniga pauza qiladi |
| [MemoryShield](https://github.com/MaatheusGois/MemoryShield) | Har bir jarayon xotira tarixi; chegaradan oshganda avtomatik o'chira oladi | Tarix va ogohlantirishlar u yerda ham bor. iClear o'chirmaydi |
| [mac-memory-guard](https://github.com/TomGranot/mac-memory-guard) | Xotira tufayli qotishdan oldin ogohlantiradi va ilovalarni birma-bir yopishga imkon beradi | Avval ogohlantiradi, qarorni inson qiladi. iClear o'zi harakat qiladi |
| [WattMate](https://wattmateapp.com/) | Ilovalar quvvatini batareya daqiqalariga aylantiradi, oldin/keyin o'lchovi bilan | Batareya daqiqalari va "nima qaytardi" o'lchovi u yerda allaqachon bor; iClear'ning batareya taxminlari yangi emas va tasdiqlanmagan |

2026-09-30 holatiga ko'ra, biz bosim uchun ETA prognozi, afsusni hisobga oluvchi
muzlatish, pauzadan oldingi ulanish/yozish himoyalari, davom ettirishdan keyingi
karantin yoki iz qayta ijrosini bu loyihalarda ham, GitHub qidiruvlarimizda ham
topmadik ([NOVELTY.md](docs/NOVELTY.md)). Topilmagani mavjud emasligini isbotlamaydi.

## Qayerda sinalgan

Yuqoridagi laboratoriya natijalari: bitta Mac (Apple M3 Pro, 18 GB, macOS 27.0.1).
Avtomatik testlar (188 ta test) GitHub'ning macOS 15 (Apple Silicon va Intel)
va macOS 26 runnerlarida ham o'tadi. iClear chegaralarini RAM hajmi, disk turi va
batareyaga moslaydi, lekin "har qanday MacBook'ga moslashadi" degani "har bir MacBook'da
sinalgan" degani emas. `iclear doctor --report` ni ishga tushiring va Mac'ingizni
[COMPATIBILITY.md](docs/COMPATIBILITY.md) ga qo'shing.

## iClean dan o'tish

iClear bu iClean ning yangi nomi. Agar iClean 0.1.0 o'rnatilgan bo'lsa, `iclear install`
(yoki `iclear migrate`) avval iClean pauza qilgan hamma narsani davom ettiradi (agar
uning xizmati ishlayotgan bo'lsa u orqali, keyin muzlatish jurnalini qayta o'qib), faqat
shundan keyin eski LaunchAgent ni to'xtatadi va o'chirib qo'yadi hamda sozlamalar, holat
va izlarni nusxalaydi. Agar eski jurnaldagi jarayon hali ham pauzada bo'lsa, hech narsani
o'zgartirmasdan to'xtaydi. Eski fayllar `iclear migrate --remove-old` ni ishga
tushirmaguningizcha joyida qoladi. `iclear migrate --dry-run` avval rejani ko'rsatadi.

## O'chirib tashlash

```sh
iclear uninstall --purge   # xizmatni to'xtatadi (hammasini davom ettiradi), LaunchAgent ni
                           # olib tashlaydi va ~/Library/Application Support/iClear ni o'chiradi
rm -rf /Applications/iClear.app
```

## Batafsil

[Arxitektura](docs/ARCHITECTURE.md) · [Xavfsizlik](docs/SAFETY.md) ·
[Tasdiqlash natijalari](docs/VALIDATION.md) · [Reliz mezonlari](docs/RELEASE_CRITERIA.md) ·
[Testlar xaritasi](docs/TEST_MATRIX.md) · [Imkoniyatlarni o'rganish](docs/FEASIBILITY.md) ·
[Qarorlar](docs/DECISIONS.md) · [Sifat](docs/QUALITY.md) · [Hissa qo'shish](CONTRIBUTING.md) ·
[Xavfsizlik siyosati](SECURITY.md) · [O'zgarishlar](CHANGELOG.md)

MIT litsenziyasi. Apple Inc. bilan bog'liq emas. macOS va MacBook Apple Inc.ning
savdo belgilaridir. iClear shunga o'xshash nomli kesh va disk tozalagichlar bilan
bog'liq emas ([NAMING.md](docs/NAMING.md)).
