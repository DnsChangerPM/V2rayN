# رادین (Radin)

یک کلاینت ویندوزیِ سبک و سریع برای **V2Ray / Xray** که با **Flutter** نوشته شده و از **ویندوز ۷ SP1 تا ویندوز ۱۱** نصب و اجرا می‌شود؛ با تنظیمات پیش‌فرضِ بهینه‌سازی‌شده برای **شبکه‌ی ایران**.

- رابط کاربری: Flutter (فارسی / انگلیسی، راست‌به‌چپ)
- هسته‌ها: **Xray-core** و **V2Ray-core** (هر دو، قابل انتخاب در تنظیمات)
- پروکسی سیستمی (بدون نیاز به ادمین) و حالت **TUN** (با Wintun)
- به‌روزرسانی سابسکریپشن، تست پینگ واقعی، تست سرعت، انتخاب خودکار سریع‌ترین سرور
- نصب‌کننده‌ی `exe` از طریق GitHub Actions و بخش **Releases**

---

## چرا این محدودیت‌ها؟ (خواندن این بخش مهم است)

سه مانع فنی برای «ویندوز ۷ تا ۱۱ با یک نصب‌کننده» وجود دارد که این پروژه هر سه را حل کرده است:

| مشکل | واقعیت | راه‌حل این پروژه |
| --- | --- | --- |
| Flutter روی ویندوز ۷ | فلاتر از نسخه‌ی ۳.۲۲ به بعد پشتیبانی از Win7/8 را حذف کرد ([اطلاعیه رسمی](https://groups.google.com/g/flutter-announce/c/s0tM5gxAgs4/m/ryxV2vZYAQAJ)) | قفل شدن روی **Flutter 3.19.6**، آخرین نسخه‌ای که روی ویندوز ۷ اجرا می‌شود |
| هسته‌ها روی ویندوز ۷ | **Go 1.20** آخرین نسخه‌ای است که روی Win7 اجرا می‌شود؛ از Go 1.21 به بعد فقط ویندوز ۱۰+ ([یادداشت انتشار Go](https://tip.golang.org/doc/go1.20)) | استفاده از بیلد رسمی **`Xray-win7-64.zip`** و کامپایل v2ray و tun2socks با **Go پچ‌شده‌ی XTLS** ([XTLS/go-win7](https://github.com/XTLS/go-win7)) |
| حالت TUN | Xray/V2Ray اصلاً Inbound از نوع TUN ندارند | **tun2socks + Wintun** (هر دو از ویندوز ۷ پشتیبانی می‌کنند) |

نتیجه: یک نصب‌کننده‌ی ۶۴ بیتی که روی ویندوز ۷ SP1 تا ۱۱ کار می‌کند، و روی ویندوز ۱۰/۱۱ از جدیدترین هسته‌ها استفاده می‌کند.

### پیش‌نیازهای ویندوز ۷ (بسیار مهم)

ویندوز ۷ باید به‌روز باشد، وگرنه برنامه اجرا نمی‌شود:

1. **KB4474419 + KB4490628** (پشتیبانی SHA-2) و ترجیحاً **KB3125574** (Convenience Rollup)
2. **KB2999226** (Universal C Runtime) — باینری‌های Go و فلاتر به آن نیاز دارند
3. **KB2670838** (Platform Update برای Direct3D 11) — موتور رندر فلاتر به D3D11 نیاز دارد
4. بسته‌ی **Visual C++ Redistributable** — نصب‌کننده در صورت نیاز خودکار نصب می‌کند

> اگر ویندوز ۷ شما به‌روز نیست، برنامه با خطای «The procedure entry point … could not be located» باز نمی‌شود. این محدودیت مایکروسافت است، نه برنامه.

---

## بهینه‌سازی برای شبکه‌ی ایران

کانفیگی که برنامه تولید می‌کند با فرض «شبکه‌ی ایران» تنظیم شده:

- **فقط IPv4 در DNS** (`queryStrategy: UseIPv4`) — چون IPv6 در اکثر ISPهای ایران یا خراب است یا باعث تأخیر طولانی می‌شود.
- **دامنه‌ها و IPهای ایرانی مستقیم** (`geosite:category-ir` و `geoip:ir`) — ترافیک داخلی نه ترافیک مصرف می‌کند نه تأخیر اضافه.
- **DNS ایرانی برای دامنه‌های داخلی** و **DoH از داخل تونل** برای بقیه — جلوی نشت و مسمومیت DNS را می‌گیرد.
- **مسدود کردن QUIC (UDP/443)** — UDP در ایران به‌شدت محدود می‌شود؛ بستن آن باعث می‌شود مرورگر به TCP/TLS برگردد و معمولاً سرعت بهتر می‌شود.
- **Mux خاموش** — روی لینک‌های پرنویز نتیجه‌ی معکوس می‌دهد.
- **Sniffing با `routeOnly`** — تصمیم‌گیری مسیریابی با دامنه‌ی واقعی بدون نشت IP.
- **تکه‌تکه کردن ClientHello** (Fragmentation، فقط Xray) — برای عبور از DPI؛ از تنظیمات قابل فعال‌سازی است.
- **انتخاب خودکار سریع‌ترین سرور** با `observatory` + `leastPing`.
- **پشتیبانی کامل از VLESS + REALITY + XTLS-Vision** (معمول‌ترین کانفیگ‌های امروز ایران).
- **MTU قابل تنظیم در حالت TUN** (پیش‌فرض ۱۴۲۰، مناسب PPPoE).

همه‌ی این موارد در `lib/core/config/config_builder.dart` پیاده شده‌اند و تست دارند.

---

## ساختار پروژه

```
lib/                     برنامه‌ی فلاتر
  core/config/           تولید کانفیگ Xray/V2Ray + قوانین مسیریابی
  core/model/            مدل سرور، تنظیمات، سابسکریپشن
  core/net/              پارس لینک، سابسکریپشن، تست پینگ/سرعت
  core/process/          اجرا/توقف هسته، آمار ترافیک
  core/store/            ذخیره‌سازی JSON
  core/utils/            مسیرها، نسخه
  ui/                    صفحات (سرورها، تنظیمات، گزارش‌ها، درباره)
  l10n/                  رشته‌های فارسی/انگلیسی
packages/win_shell/      پلاگین FFI خودمان (Win32):
                         سینی سیستم، پروکسی ویندوز، اجرای پروسس، TUN، UAC
build/
  installer/setup.iss    نصب‌کننده‌ی Inno Setup (MinVersion=6.1)
  tools/                 اسکریپت‌های ساخت و تعیین نسخه
windows_custom/          آیکون برنامه (داخل windows/ کپی می‌شود)
.github/workflows/       release.yml و ci.yml
```

> پوشه‌ی `windows/` عمداً در گیت نیست؛ با `flutter create` در CI ساخته می‌شود (اسکریپت `build/tools/New-WindowsRunner.ps1`).

---

## توسعه‌ی محلی

```bash
# فقط برای ویندوز
flutter --version        # باید 3.19.6 باشد
flutter config --enable-windows-desktop
flutter pub get
powershell -File build/tools/New-WindowsRunner.ps1 -Version 0.0.0-dev
flutter build windows --release --dart-define=APP_VERSION=0.0.0-dev
```

برای اجرا باید هسته‌ها در کنار exe قرار بگیرند:

```
build/windows/x64/runner/Release/core/{xray.exe,xray-win7.exe,v2ray.exe,v2ray-win7.exe,tun2socks.exe,tun2socks-win7.exe,wintun.dll,geoip.dat,geosite.dat}
```

در CI این کار با `build/tools/fetch-cores.sh` انجام می‌شود.

---

## انتشار نسخه با GitHub Action

از تب **Actions** → **Release** → **Run workflow** اجرا کنید.

### پرسشِ نسخه (Auto-bump)

اکشن ابتدا آخرین تگ را می‌خواند و **نسخه‌ی پیشنهادی** را چاپ و در خلاصه‌ی اجرا نمایش می‌دهد؛ شما یا همان را تأیید می‌کنید یا نسخه‌ی دلخواه را می‌نویسید:

| ورودی | توضیح |
| --- | --- |
| `bump` | `patch` (پیش‌فرض)، `minor`، `major` یا `none` |
| `version` | نسخه‌ی دقیق (مثل `1.4.0`)؛ اگر پر شود، بر `bump` غلبه می‌کند |
| `prerelease` | `none` / `alpha` / `beta` / `rc` |
| `prerelease_number` | شماره‌ی پیش‌انتشار (مثل `1` → `1.4.0-beta.1`) |
| `release_notes` | یادداشت انتشار؛ اگر خالی باشد از پیام‌های کامیت ساخته می‌شود |
| `draft` | ساخت انتشار به صورت پیش‌نویس |
| `publish` | انتشار واقعی در Releases |
| `dry_run` | **فقط نسخه را حساب می‌کند و چیزی نمی‌سازد** — برای دیدن پیشنهاد قبل از تأیید |
| `build_win7_cores` | کامپایل v2ray/tun2socks با Go پچ‌شده برای Win7 |
| `xray_version` / `v2ray_version` / `tun2socks_version` | پین کردن نسخه‌ی هسته‌ها (`latest` پیش‌فرض) |
| `flutter_version` | پیش‌فرض `3.19.6` (آخرین نسخه با پشتیبانی Win7) |

مثال: آخرین تگ `v1.2.3` است → با `bump=patch` نسخه‌ی `1.2.4` و تگ `v1.2.4` ساخته می‌شود.
اگر `prerelease=beta` و `prerelease_number=2` باشد → `1.2.4-beta.2`.

نسخه‌ی انتخاب‌شده در `version.txt` ذخیره و کامیت می‌شود، پس اجرای بعدی از همان‌جا ادامه می‌دهد.

### خروجی‌های هر انتشار

- `Radin-Setup-<version>.exe` — نصب‌کننده (ویندوز ۷ SP1 تا ۱۱، x64)
- `Radin-<version>-portable.zip` — نسخه‌ی پرتابل بدون نصب
- `SHA256SUMS.txt` — چک‌سام فایل‌ها

### مراحل گردش‌کار

1. **Version** — محاسبه و اعتبارسنجی نسخه، بررسی تکراری نبودن تگ، ساخت یادداشت انتشار
2. **Cores** — دریافت بیلدهای رسمی + کامپایل نسخه‌های Win7
3. **Flutter app** — ساخت با Flutter 3.19.6 روی ویندوز
4. **Installer** — Inno Setup + زیپ پرتابل + چک‌سام
5. **Publish release** — ساخت تگ و انتشار

هر بار push به هر برنچی، گردش‌کار **CI** را هم اجرا می‌کند (تحلیل، فرمت، تست و کامپایل ویندوز).

---

## یادداشت‌های امنیتی

- پروکسی سیستمی فقط برای کاربر جاری تغییر می‌کند (`HKCU`) و مقدار قبلی ذخیره می‌شود تا هنگام خروج برگردانده شود؛ حتی اگر برنامه کرش کند.
- در حالت TUN برنامه باید با دسترسی Administrator اجرا شود (نیاز درایور Wintun).
- سابسکریپشن‌ها با `badCertificateCallback` پذیرفته می‌شوند چون بسیاری از پنل‌های ایرانی گواهی معتبر ندارند.

---

## مجوز و منابع

هسته‌ها پروژه‌های جداگانه‌ای هستند:

- [XTLS/Xray-core](https://github.com/XTLS/Xray-core)
- [v2fly/v2ray-core](https://github.com/v2fly/v2ray-core)
- [xjasonlyu/tun2socks](https://github.com/xjasonlyu/tun2socks)
- [WireGuard/wintun](https://github.com/wireguard/wintun)
- [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)
- [XTLS/go-win7](https://github.com/XTLS/go-win7)

این مخزن فقط یک کلاینت است و هیچ سروری ارائه نمی‌دهد.
