# iClear (avvalgi nomi iClean)

[![CI](https://github.com/urrra39/iClear/actions/workflows/ci.yml/badge.svg)](https://github.com/urrra39/iClear/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **1.0 sari ishlab chiqilayotgan versiya** (oxirgi reliz: iClean 0.1.0 beta). Sintetik
> sinov jarayonlari bilan va bitta Mac'da (Apple M3 Pro, macOS 27.0.1) sinalgan.
> Haqiqiy ilovalarda Faol rejim hali tasdiqlanmagan. Dastur Kuzatish rejimida
> boshlanadi, u faqat nima qilgan bo'lardi, shuni yozib boradi. Loyiha nomi iClean dan
> iClear ga o'zgartirildi; "iClean dan o'tish" bo'limiga qarang.

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
[O'lchovlar](docs/BENCHMARKS.md) · [Savol-javob](docs/FAQ.md) (hujjatlar ingliz tilida)

<p align="center"><img src="docs/images/menu-uz.png" width="360" alt="iClear menyusi: Mac salomatligi 100/100, xotira me'yorida, Kuzatish rejimi"></p>

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

- Haqiqiy bosim ostida bo'sh turgan fon ilovalarini **pauza qiladi va davom
  ettiradi**: butun jarayonlar daraxti, faqat ko'rinadigan oynasi yo'q ilovalar, faqat
  barcha xavfsizlik tekshiruvlaridan o'tgandan keyin. Ilova faollashtirilganda birinchi
  ish uni davom ettirish bo'ladi.
- **`iclear why`**: "Mac nega hozir sekin?" degan savolga o'lchangan ma'lumotlardan
  (bosim, svop, eng katta ilovalar, protsessorni band qilganlar, qizish, kam disk, Low
  Power Mode) tartiblangan, oddiy tildagi javob.
- **Mac salomatligi bahosi** (0-100, formula [ARCHITECTURE.md](docs/ARCHITECTURE.md)
  da) menyu panelida, kichik svop grafigi bilan.
- **Runaway himoyasi**: protsessorni aylantirayotgan yoki xotirada tinmay o'sayotgan
  ilovani payqaydi va bir marta xabar beradi. Hech narsani o'zi yopmaydi.
- **Profillar**: Ish, Batareyani tejash, Taqdimot va Dasturlash. Batareyaga o'tganda,
  ekran ko'zgulanganda yoki ulashilganda, yoki jadval bo'yicha avtomatik almashadi.
- **Fokus xavfsiz rejimi**: qo'ng'iroq, ekran ulashish, ko'zgulash yoki to'liq ekran
  paytida avtomatik amal bajarilmaydi.
- **Avval Kuzatish rejimi**: uni Faol rejimga o'tkazmaguningizcha, iClear faqat nima
  qilgan bo'lardi, shuni yozib boradi.
- **Bekor qilish, Hammasini davom ettirish va favqulodda tugmalar**
  (Control-Option-Command-T, menyu ilovasi ishlab turganda). Hammasini davom ettirish
  (menyu yoki `iclear thaw --all`) xizmat ishdan chiqqan bo'lsa ham ishlaydi; u
  muzlatish jurnalini qayta o'qiydi.
- **Kunlik/haftalik hisobot**: faqat o'lchangan raqamlar, va "bu ilova vaqtning 92%
  ida bo'sh turdi, qo'shamizmi?" yoki "buni bir daqiqa ichida uch marta qayta
  ochdingiz, chiqarib tashlaymizmi?" kabi takliflar.
- **Tushuntiriladi**: har bir amalning sabab kodlari bor; `iclear explain <ilova>`
  ilova nega pauza qilingani yoki qilinmaganini ko'rsatadi.

Asosiy imkoniyatlar, har biri uchun nima o'lchangani va nimasi yoqilgan yoki
o'chirilgan holda chiqishi [SIGNATURE_FEATURES.md](docs/SIGNATURE_FEATURES.md) da:
bosim prognozi, afsusni hisobga oluvchi qarorlar, odat statistikasi, ulanish va yozish
himoyalari, davom ettirishdan keyingi salomatlik tekshiruvi va karantin, iz (trace)
qayta ijrosi (`iclear simulate`), ish to'plamlari (ixtiyoriy bosqichma-bosqich davom
ettirish bilan), va RAM hajmi bo'yicha taxmin.

## O'lchangan natijalar

[BENCHMARKS.md](docs/BENCHMARKS.md) dan. Apple M3 Pro, 18 GB, macOS 27.0.1,
2026-09-30. Sintetik sinov jarayonlari, haqiqiy ilovalar emas. "(1 marta)" belgili
qatorlar yagona kuzatuvlar.

| Nima | Natija |
|---|---|
| Sun'iy bosim ostida pauza qilingan 512 MB jarayon, rezident xotira | 519 MB → 6 MB (1 marta) |
| Xuddi shunday, lekin ishlashda davom etgan jarayon, bir xil bosim | 519 MB → 518 MB (1 marta) |
| Davom ettirish signalidan jarayon ishlashigacha, 1 GB jarayon (p50 / p95) | 0.03 / 0.05 ms |
| Bosim ostida 512 MB xotirani qaytarib yuklash bilan davom ettirish | 80 ms (1 marta) |
| 4 × 128 MB ilovani ketma-ket va hammasini birdan davom ettirish: birinchi ilova tayyor / to'rttasi ham tayyor | 16.7 / 71.9 ms va 37.7 / 40.1 ms (1 marta; shuning uchun bosqichma-bosqich davom ettirish ixtiyoriy) |
| Xizmatning bo'sh holdagi protsessor sarfi (o'rnatilgan, 120 s oyna) | 0.35% |
| Xizmatning rezident xotirasi | 40 MB |

Hali o'lchanmagan: haqiqiy ilovalardan qaytarib olingan xotira, haqiqiy ilovalarning
davom etish kechikishi, energiya tejash, Intel Mac'lar, 8 GB Mac'lar.

## Ruxsatlar

| Ruxsat | Majburiymi? | Nima uchun | Rad etilsa |
|---|---|---|---|
| hech qanday | | pauza, davom ettirish, `why`, salomatlik bahosi, himoyalar | hammasi ishlaydi |
| Maxsus imkoniyatlar (Accessibility) | ixtiyoriy | davom ettirilgan ilova javob berishini tekshirish; kechikishni o'lchash | davom ettirishdan keyingi qotib qolish aniqlanmaydi; kechikish "o'lchanmagan" bo'ladi |
| Kiritishni kuzatish (Input Monitoring) | ixtiyoriy | tajribaviy oldindan davom ettirish (o'chirilgan) | hech narsa o'zgarmaydi |
| Ekranni yozib olish | ishlatilmaydi | | |

Root kerak emas, yadro kengaytmasi yo'q, SIP o'zgartirilmaydi, tarmoqqa ulanmaydi,
telemetriya yo'q.

## O'rnatish

macOS 13 va undan yangilari, Apple Silicon va Intel uchun qurilgan (universal ikkilik
fayl). Hozircha tasdiqlangani: build va to'liq testlar CI da macOS 15.7 (Apple Silicon va
Intel) va macOS 26.6 da, mahalliy ravishda macOS 27.0.1 (Apple M3 Pro) da. macOS 13 va
14 tasdiqlanmagan.

**Reliz.** Oxirgi chiqarilgan build nom o'zgarishidan oldingi
[iClean 0.1.0 sinov relizi](https://github.com/urrra39/iClear/releases/tag/v0.1.0): uning
fayllari va buyruqlari eski nomlarda (`iclean`, `icleand`). iClear buildlari keyingi
reliz bilan chiqariladi. Ungacha manba koddan quring.

**Manba koddan:**

```sh
git clone https://github.com/urrra39/iClear.git && cd iClear
scripts/build-release.sh           # universal ikkilik fayllar, dist/iClear.app
cp -R dist/iClear.app /Applications/
```

Mahalliy build ad-hoc imzolangan: agar macOS birinchi ishga tushirishni to'xtatsa,
ilovani o'ng tugma bilan bosing, Open ni tanlang va tasdiqlang.
Buyruq qatori vositalari `dist/iclear-<version>/` da va ilova ichida
`iClear.app/Contents/Helpers/` da.

Homebrew tap rejalashtirilgan, lekin hali chiqarilmagan. Formula va cask shablonlari
[`packaging/homebrew/`](packaging/homebrew/) da.

## Tez boshlash (60 soniya)

```sh
iclear install          # foydalanuvchi xizmatini Kuzatish rejimida ishga tushiradi
iclear status           # u nimani ko'rmoqda va nima qilgan bo'lardi
iclear why              # Mac nega hozir sekin?
iclear explain Chrome   # ilova nega pauza qilindi yoki qilinmadi
# ...Mac'ingizdan bir kun foydalaning, keyin:
iclear stats --days 1   # u nima qilgan bo'lardi va taxminiy afsus darajasi
iclear mode active      # unga amal qilishga ruxsat bering
```

Ilova bilan: iClear ni Applications dan oching. Menyuda xuddi shu ma'lumotlar bor,
"iClear'ni ishga tushirish" esa xizmatni o'rnatadi.

Favqulodda holat: **Control-Option-Command-T** yoki `iclear thaw --all` hammasini
davom ettiradi.

## Xavfsizlik modeli

Qisqacha: har bir pauzadan oldin muzlatish jurnali yoziladi, va xizmat ishdan chiqsa
(hatto `kill -9` bilan ham), alohida kuzatuvchi (watchdog) jarayon hammasini davom
ettiradi. Har bir signal oldidan PID, boshlanish vaqti va egasi qayta tekshiriladi.
Himoyalangan to'plamni (tizim, terminallar, AI dasturlash agentlari, parol
menejerlari, sinxronlash, VPN, kiritish va maxsus imkoniyat vositalari) hech qanday
qoida bilan pauza qilib bo'lmaydi. Daraxtlar "hammasi yoki hech biri" tamoyili bilan
pauza qilinadi. Pauza vaqti (4 soat) va umumiy hajmi (RAM ning 50%) cheklangan. Audio,
qo'ng'iroq, yuklab olish, tarmoq faolligi, dev-server mijozlari, yaqinda yozilgan
fayllar yoki lock fayllari bo'lgan ilovalar o'tkazib yuboriladi. Har bir qoidaning
testi bor; [SAFETY.md](docs/SAFETY.md) ga qarang.

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

2026-09-30 holatiga ko'ra, biz bosim uchun ETA prognozi, afsusni hisobga oluvchi
muzlatish, pauzadan oldingi ulanish/yozish himoyalari, davom ettirishdan keyingi
karantin yoki iz qayta ijrosini bu loyihalarda ham, GitHub qidiruvlarimizda ham
topmadik ([NOVELTY.md](docs/NOVELTY.md)). Topilmagani mavjud emasligini isbotlamaydi.

## Qayerda sinalgan

Haqiqiy foydalanish, o'lchovlar va o'rnatish/o'chirish: hozircha bitta Mac (Apple M3 Pro,
18 GB, macOS 27.0.1). Avtomatik testlar GitHub'ning macOS 15.7 (Apple Silicon va Intel)
va macOS 26.6 runnerlarida ham o'tadi. iClear chegaralarini
RAM hajmi, disk turi va batareyaga moslaydi, lekin "har qanday MacBook'ga moslashadi"
degani "har bir MacBook'da sinalgan" degani emas. `iclear doctor --report` ni ishga
tushiring va Mac'ingizni [COMPATIBILITY.md](docs/COMPATIBILITY.md) ga qo'shing.

## iClean dan o'tish

iClear bu iClean ning yangi nomi. Agar iClean 0.1.0 o'rnatilgan bo'lsa, `iclear install`
(yoki `iclear migrate`) avval iClean pauza qilgan hamma narsani davom ettiradi (agar
uning xizmati ishlayotgan bo'lsa u orqali, keyin muzlatish jurnalini qayta o'qib), faqat
shundan keyin eski LaunchAgent ni to'xtatadi va o'chirib qo'yadi hamda sozlamalar, holat
va izlarni nusxalaydi. Agar eski jurnaldagi jarayon hali ham pauzada bo'lsa, hech narsani
o'zgartirmasdan to'xtaydi. Eski fayllar `iclear migrate --remove-old` ni ishga
tushirmaguningizcha joyida qoladi. `iclear migrate --dry-run` avval rejani ko'rsatadi.
Alohida uy kataloglarida soxta eski o'rnatma bilan sinalgan (`MigrationTests`), jumladan
ishdan chiqqan eski xizmat va yarim yozilgan jurnal bilan.

## O'chirib tashlash

```sh
iclear uninstall --purge   # xizmatni to'xtatadi (hammasini davom ettiradi), LaunchAgent ni
                           # olib tashlaydi va ~/Library/Application Support/iClear ni o'chiradi
rm -rf /Applications/iClear.app
```

## Batafsil

[Arxitektura](docs/ARCHITECTURE.md) · [Xavfsizlik](docs/SAFETY.md) ·
[Imkoniyatlarni o'rganish](docs/FEASIBILITY.md) · [Qarorlar](docs/DECISIONS.md) ·
[Iz formati](docs/TRACE_FORMAT.md) · [Hissa qo'shish](CONTRIBUTING.md) ·
[Xavfsizlik siyosati](SECURITY.md) · [O'zgarishlar](CHANGELOG.md)

MIT litsenziyasi. Apple Inc. bilan bog'liq emas. macOS va MacBook Apple Inc.ning
savdo belgilaridir. iClear shunga o'xshash nomli kesh va disk tozalagichlar bilan
bog'liq emas ([NAMING.md](docs/NAMING.md)).
