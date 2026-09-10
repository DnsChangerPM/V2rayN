/// Minimal hand rolled localization (Persian + English).
///
/// The app only needs a handful of strings, so a full `gen_l10n` setup would be
/// overhead. Every getter falls back to English when a key is missing.
library;

import 'package:flutter/widgets.dart';

class Strings {
  const Strings._(this._values, this.localeName);

  final Map<String, String> _values;
  final String localeName;

  static const Strings fa = Strings._(_fa, 'fa');
  static const Strings en = Strings._(_en, 'en');

  static Strings of(Locale? locale) {
    final code = locale?.languageCode ?? 'fa';
    return code == 'en' ? en : fa;
  }

  bool get isRtl => localeName == 'fa';

  String t(String key) => _values[key] ?? _en[key] ?? key;

  // -- shell ----------------------------------------------------------------
  String get appTitle => t('appTitle');
  String get servers => t('servers');
  String get settings => t('settings');
  String get logs => t('logs');
  String get about => t('about');
  String get showWindow => t('showWindow');
  String get hideWindow => t('hideWindow');
  String get minimizeToTray => t('minimizeToTray');
  String get exitApp => t('exitApp');

  // -- status ---------------------------------------------------------------
  String get connect => t('connect');
  String get disconnect => t('disconnect');
  String get connecting => t('connecting');
  String get disconnecting => t('disconnecting');
  String get statusRunning => t('statusRunning');
  String get statusStopped => t('statusStopped');
  String get connectionFailed => t('connectionFailed');
  String get connectedTo => t('connectedTo');
  String get connectingTo => t('connectingTo');
  String get selectServer => t('selectServer');
  String get noServers => t('noServers');
  String get noServersHint => t('noServersHint');

  // -- servers --------------------------------------------------------------
  String get add => t('add');
  String get edit => t('edit');
  String get delete => t('delete');
  String get duplicate => t('duplicate');
  String get copyLink => t('copyLink');
  String get copyLinkDone => t('copyLinkDone');
  String get importClipboard => t('importClipboard');
  String get importClipboardDone => t('importClipboardDone');
  String get importClipboardEmpty => t('importClipboardEmpty');
  String get testDelay => t('testDelay');
  String get testAll => t('testAll');
  String get testing => t('testing');
  String get speedTest => t('speedTest');
  String get traffic => t('traffic');
  String get upload => t('upload');
  String get download => t('download');
  String get total => t('total');
  String get used => t('used');
  String get expire => t('expire');
  String get notAvailable => t('notAvailable');
  String get unknown => t('unknown');

  // -- subscription ---------------------------------------------------------
  String get subscriptions => t('subscriptions');
  String get addSubscription => t('addSubscription');
  String get updateSubscription => t('updateSubscription');
  String get updateAll => t('updateAll');
  String get updated => t('updated');
  String get subscriptionUrl => t('subscriptionUrl');
  String get subscriptionName => t('subscriptionName');

  // -- editor ---------------------------------------------------------------
  String get remark => t('remark');
  String get address => t('address');
  String get port => t('port');
  String get protocol => t('protocol');
  String get uuid => t('uuid');
  String get password => t('password');
  String get method => t('method');
  String get transport => t('transport');
  String get host => t('host');
  String get path => t('path');
  String get sni => t('sni');
  String get security => t('security');
  String get none => t('none');
  String get tls => t('tls');
  String get reality => t('reality');
  String get flow => t('flow');
  String get fingerprint => t('fingerprint');
  String get allowInsecure => t('allowInsecure');
  String get publicKey => t('publicKey');
  String get shortId => t('shortId');
  String get spiderX => t('spiderX');
  String get udp => t('udp');
  String get shareQr => t('shareQr');

  // -- settings -------------------------------------------------------------
  String get general => t('general');
  String get networkSection => t('networkSection');
  String get routing => t('routing');
  String get advancedSection => t('advancedSection');
  String get routingGlobal => t('routingGlobal');
  String get routingSmartIran => t('routingSmartIran');
  String get routingCustom => t('routingCustom');
  String get routingHint => t('routingHint');
  String get proxyMode => t('proxyMode');
  String get modeSystemProxy => t('modeSystemProxy');
  String get modeTun => t('modeTun');
  String get modeBoth => t('modeBoth');
  String get tunHint => t('tunHint');
  String get core => t('core');
  String get coreXray => t('coreXray');
  String get coreV2ray => t('coreV2ray');
  String get coreFlavour => t('coreFlavour');
  String get flavourAuto => t('flavourAuto');
  String get flavourLegacy => t('flavourLegacy');
  String get flavourModern => t('flavourModern');
  String get coreVersionLabel => t('coreVersionLabel');
  String get httpPort => t('httpPort');
  String get socksPort => t('socksPort');
  String get apiPort => t('apiPort');
  String get allowLan => t('allowLan');
  String get dns => t('dns');
  String get dnsRemote => t('dnsRemote');
  String get dnsIran => t('dnsIran');
  String get dnsIpv4Only => t('dnsIpv4Only');
  String get dnsCache => t('dnsCache');
  String get blockAds => t('blockAds');
  String get blockQuic => t('blockQuic');
  String get fragment => t('fragment');
  String get fragmentHint => t('fragmentHint');
  String get fragmentLength => t('fragmentLength');
  String get fragmentInterval => t('fragmentInterval');
  String get bypassIran => t('bypassIran');
  String get autoSelect => t('autoSelect');
  String get probeUrl => t('probeUrl');
  String get muxEnabled => t('muxEnabled');
  String get customBypass => t('customBypass');
  String get customProxy => t('customProxy');
  String get customRules => t('customRules');
  String get customRulesHint => t('customRulesHint');
  String get tunName => t('tunName');
  String get tunAddress => t('tunAddress');
  String get tunGateway => t('tunGateway');
  String get tunDns => t('tunDns');
  String get tunAutoRoute => t('tunAutoRoute');
  String get mtuLabel => t('mtuLabel');
  String get startMinimized => t('startMinimized');
  String get closeToTray => t('closeToTray');
  String get autoStart => t('autoStart');
  String get autoConnect => t('autoConnect');
  String get autoReconnect => t('autoReconnect');
  String get language => t('language');
  String get persian => t('persian');
  String get english => t('english');
  String get system => t('system');
  String get theme => t('theme');
  String get themeLight => t('themeLight');
  String get themeDark => t('themeDark');
  String get themeSystem => t('themeSystem');
  String get openDataFolder => t('openDataFolder');
  String get openCoreFolder => t('openCoreFolder');
  String get openLogsFolder => t('openLogsFolder');
  String get logLevel => t('logLevel');

  // -- dialogs --------------------------------------------------------------
  String get save => t('save');
  String get cancel => t('cancel');
  String get confirm => t('confirm');
  String get close => t('close');
  String get reset => t('reset');
  String get deleteTitle => t('deleteTitle');
  String get deleteMessage => t('deleteMessage');
  String get adminRequiredTitle => t('adminRequiredTitle');
  String get adminRequiredBody => t('adminRequiredBody');
  String get ok => t('ok');
  String get error => t('error');
  String get warning => t('warning');
  String get success => t('success');
  String get dismiss => t('dismiss');
  String get clearLogs => t('clearLogs');
  String get logsEmpty => t('logsEmpty');

  // -- about ----------------------------------------------------------------
  String get version => t('version');
  String get build => t('build');
  String get osLabel => t('osLabel');
  String get coreLabel => t('coreLabel');
  String get repository => t('repository');
  String get updateAvailable => t('updateAvailable');
  String get upToDate => t('upToDate');
  String get checkUpdate => t('checkUpdate');
  String get aboutBody => t('aboutBody');
}

const Map<String, String> _fa = <String, String>{
  'appTitle': 'رادین',
  'servers': 'سرورها',
  'settings': 'تنظیمات',
  'logs': 'گزارش‌ها',
  'about': 'درباره',
  'showWindow': 'نمایش پنجره',
  'hideWindow': 'مخفی کردن',
  'minimizeToTray': 'کوچک‌کردن به سینی',
  'exitApp': 'خروج',
  'connect': 'اتصال',
  'disconnect': 'قطع اتصال',
  'connecting': 'در حال اتصال…',
  'disconnecting': 'در حال قطع…',
  'statusRunning': 'متصل',
  'statusStopped': 'قطع',
  'connectionFailed': 'اتصال ناموفق بود',
  'connectedTo': 'متصل به',
  'connectingTo': 'در حال اتصال به',
  'selectServer': 'یک سرور انتخاب کنید',
  'noServers': 'سروری وجود ندارد',
  'noServersHint': 'از طریق دکمهٔ «افزودن» یا یک سابسکریپشن سرور اضافه کنید.',
  'add': 'افزودن',
  'edit': 'ویرایش',
  'delete': 'حذف',
  'duplicate': 'تکثیر',
  'copyLink': 'کپی لینک',
  'copyLinkDone': 'لینک کپی شد',
  'importClipboard': 'دریافت از کلیپ‌بورد',
  'importClipboardDone': 'سرور(ها) اضافه شد',
  'importClipboardEmpty': 'کلیپ‌بورد خالی است یا لینک معتبری ندارد',
  'testDelay': 'تست پینگ',
  'testAll': 'تست همه',
  'testing': 'در حال تست…',
  'speedTest': 'تست سرعت',
  'traffic': 'ترافیک',
  'upload': 'ارسال',
  'download': 'دریافت',
  'total': 'کل',
  'used': 'مصرف‌شده',
  'expire': 'انقضا',
  'notAvailable': '—',
  'unknown': 'نامشخص',
  'subscriptions': 'سابسکریپشن‌ها',
  'addSubscription': 'افزودن سابسکریپشن',
  'updateSubscription': 'به‌روزرسانی',
  'updateAll': 'به‌روزرسانی همه',
  'updated': 'به‌روز شد',
  'subscriptionUrl': 'نشانی سابسکریپشن',
  'subscriptionName': 'نام دلخواه',
  'remark': 'نام',
  'address': 'نشانی سرور',
  'port': 'پورت',
  'protocol': 'پروتکل',
  'uuid': 'UUID / شناسه',
  'password': 'رمز عبور',
  'method': 'روش رمزنگاری',
  'transport': 'انتقال',
  'host': 'هاست',
  'path': 'مسیر',
  'sni': 'SNI',
  'security': 'امنیت',
  'none': 'ندارد',
  'tls': 'TLS',
  'reality': 'REALITY',
  'flow': 'Flow',
  'fingerprint': 'اثر انگشت TLS',
  'allowInsecure': 'عدم اعتبارسنجی گواهی',
  'publicKey': 'کلید عمومی',
  'shortId': 'Short ID',
  'spiderX': 'SpiderX',
  'udp': 'UDP',
  'shareQr': 'نمایش QR',
  'general': 'عمومی',
  'networkSection': 'شبکه',
  'routing': 'مسیریابی',
  'advancedSection': 'پیشرفته',
  'routingGlobal': 'کل ترافیک از پروکسی',
  'routingSmartIran': 'هوشمند (ایران مستقیم)',
  'routingCustom': 'سفارشی',
  'routingHint': 'در حالت هوشمند، سایت‌های ایرانی و شبکهٔ محلی مستقیم و بقیه از تونل عبور می‌کنند.',
  'proxyMode': 'روش اتصال',
  'modeSystemProxy': 'پروکسی سیستمی',
  'modeTun': 'TUN (کل سیستم)',
  'modeBoth': 'هر دو',
  'tunHint': 'حالت TUN به دسترسی مدیر نیاز دارد و از درایور Wintun استفاده می‌کند.',
  'core': 'هسته',
  'coreXray': 'Xray-core (پیشنهادی)',
  'coreV2ray': 'V2Ray-core',
  'coreFlavour': 'نسخهٔ هسته',
  'flavourAuto': 'خودکار (بر اساس ویندوز)',
  'flavourLegacy': 'سازگار با ویندوز ۷',
  'flavourModern': 'جدید (فقط ویندوز ۱۰/۱۱)',
  'coreVersionLabel': 'نسخهٔ هسته',
  'httpPort': 'پورت HTTP',
  'socksPort': 'پورت SOCKS',
  'apiPort': 'پورت API',
  'allowLan': 'اشتراک در شبکهٔ محلی',
  'dns': 'DNS',
  'dnsRemote': 'DNS رمزنگاری‌شده (DoH)',
  'dnsIran': 'DNS ایرانی (برای دامنه‌های .ir)',
  'dnsIpv4Only': 'فقط IPv4',
  'dnsCache': 'کش DNS',
  'blockAds': 'مسدود کردن تبلیغات',
  'blockQuic': 'مسدود کردن QUIC (UDP/443)',
  'fragment': 'تکه‌تکه کردن بسته‌ها',
  'fragmentHint': 'ارسال ClientHello به‌صورت تکه‌تکه؛ برای عبور از DPI مفید است.',
  'fragmentLength': 'طول تکه‌ها',
  'fragmentInterval': 'فاصله (ms)',
  'bypassIran': 'عبور مستقیم دامنه‌های ایرانی',
  'autoSelect': 'انتخاب خودکار سریع‌ترین سرور',
  'probeUrl': 'نشانی سنجش',
  'muxEnabled': 'Mux (توصیه نمی‌شود)',
  'customBypass': 'دامنه‌های مستقیم',
  'customProxy': 'دامنه‌های پروکسی‌شده',
  'customRules': 'قوانین سفارشی (JSON)',
  'customRulesHint': 'آرایه‌ای از قوانین مسیریابی Xray، مثال:\n[{"type":"field","domain":["domain:example.com"],"outboundTag":"direct"}]',
  'tunName': 'نام کارت شبکه',
  'tunAddress': 'نشانی TUN',
  'tunGateway': 'دروازهٔ TUN',
  'tunDns': 'DNS در حالت TUN',
  'tunAutoRoute': 'مسیریابی خودکار',
  'mtuLabel': 'MTU',
  'startMinimized': 'شروع در سینی',
  'closeToTray': 'بستن به سینی',
  'autoStart': 'اجرا با شروع ویندوز',
  'autoConnect': 'اتصال خودکار هنگام اجرا',
  'autoReconnect': 'اتصال مجدد خودکار',
  'language': 'زبان',
  'persian': 'فارسی',
  'english': 'English',
  'system': 'سیستم',
  'theme': 'پوسته',
  'themeLight': 'روشن',
  'themeDark': 'تیره',
  'themeSystem': 'همراه سیستم',
  'openDataFolder': 'پوشهٔ تنظیمات',
  'openCoreFolder': 'پوشهٔ هسته‌ها',
  'openLogsFolder': 'پوشهٔ گزارش‌ها',
  'logLevel': 'سطح گزارش',
  'save': 'ذخیره',
  'cancel': 'انصراف',
  'confirm': 'تأیید',
  'close': 'بستن',
  'reset': 'بازنشانی',
  'deleteTitle': 'حذف سرور',
  'deleteMessage': 'آیا از حذف این سرور مطمئن هستید؟',
  'adminRequiredTitle': 'دسترسی مدیر لازم است',
  'adminRequiredBody': 'حالت TUN نیاز به اجرای برنامه به عنوان مدیر (Administrator) دارد.',
  'ok': 'باشه',
  'error': 'خطا',
  'warning': 'هشدار',
  'success': 'انجام شد',
  'dismiss': 'بستن',
  'clearLogs': 'پاک کردن گزارش',
  'logsEmpty': 'گزارشی ثبت نشده است.',
  'version': 'نسخه',
  'build': 'شماره ساخت',
  'osLabel': 'سیستم‌عامل',
  'coreLabel': 'هسته',
  'repository': 'مخزن پروژه',
  'updateAvailable': 'نسخهٔ جدید در دسترس است',
  'upToDate': 'برنامه به‌روز است',
  'checkUpdate': 'بررسی به‌روزرسانی',
  'aboutBody': 'یک کلاینت سبک و سریع برای V2Ray و Xray با تنظیمات بهینه‌سازی‌شده برای شبکهٔ ایران. پشتیبانی از ویندوز ۷ تا ۱۱.',
};

const Map<String, String> _en = <String, String>{
  'appTitle': 'Radin',
  'servers': 'Servers',
  'settings': 'Settings',
  'logs': 'Logs',
  'about': 'About',
  'showWindow': 'Show window',
  'hideWindow': 'Hide',
  'minimizeToTray': 'Minimize to tray',
  'exitApp': 'Exit',
  'connect': 'Connect',
  'disconnect': 'Disconnect',
  'connecting': 'Connecting…',
  'disconnecting': 'Disconnecting…',
  'statusRunning': 'Connected',
  'statusStopped': 'Disconnected',
  'connectionFailed': 'Connection failed',
  'connectedTo': 'Connected to',
  'connectingTo': 'Connecting to',
  'selectServer': 'Select a server',
  'noServers': 'No servers yet',
  'noServersHint': 'Add a server manually or import a subscription.',
  'add': 'Add',
  'edit': 'Edit',
  'delete': 'Delete',
  'duplicate': 'Duplicate',
  'copyLink': 'Copy link',
  'copyLinkDone': 'Link copied',
  'importClipboard': 'Import from clipboard',
  'importClipboardDone': 'Server(s) imported',
  'importClipboardEmpty': 'Clipboard is empty or has no valid link',
  'testDelay': 'Test delay',
  'testAll': 'Test all',
  'testing': 'Testing…',
  'speedTest': 'Speed test',
  'traffic': 'Traffic',
  'upload': 'Upload',
  'download': 'Download',
  'total': 'Total',
  'used': 'Used',
  'expire': 'Expires',
  'notAvailable': '—',
  'unknown': 'Unknown',
  'subscriptions': 'Subscriptions',
  'addSubscription': 'Add subscription',
  'updateSubscription': 'Update',
  'updateAll': 'Update all',
  'updated': 'Updated',
  'subscriptionUrl': 'Subscription URL',
  'subscriptionName': 'Display name',
  'remark': 'Remark',
  'address': 'Address',
  'port': 'Port',
  'protocol': 'Protocol',
  'uuid': 'UUID / ID',
  'password': 'Password',
  'method': 'Encryption method',
  'transport': 'Transport',
  'host': 'Host',
  'path': 'Path',
  'sni': 'SNI',
  'security': 'Security',
  'none': 'None',
  'tls': 'TLS',
  'reality': 'REALITY',
  'flow': 'Flow',
  'fingerprint': 'TLS fingerprint',
  'allowInsecure': 'Allow insecure certificate',
  'publicKey': 'Public key',
  'shortId': 'Short ID',
  'spiderX': 'SpiderX',
  'udp': 'UDP',
  'shareQr': 'Show QR',
  'general': 'General',
  'networkSection': 'Network',
  'routing': 'Routing',
  'advancedSection': 'Advanced',
  'routingGlobal': 'Global (everything proxied)',
  'routingSmartIran': 'Smart (Iran direct)',
  'routingCustom': 'Custom',
  'routingHint': 'In smart mode Iranian sites and the LAN go direct, everything else uses the tunnel.',
  'proxyMode': 'Connection mode',
  'modeSystemProxy': 'System proxy',
  'modeTun': 'TUN (whole system)',
  'modeBoth': 'Both',
  'tunHint': 'TUN mode needs administrator rights and uses the Wintun driver.',
  'core': 'Core',
  'coreXray': 'Xray-core (recommended)',
  'coreV2ray': 'V2Ray-core',
  'coreFlavour': 'Core build',
  'flavourAuto': 'Automatic (based on Windows)',
  'flavourLegacy': 'Windows 7 compatible',
  'flavourModern': 'Modern (Windows 10/11 only)',
  'coreVersionLabel': 'Core version',
  'httpPort': 'HTTP port',
  'socksPort': 'SOCKS port',
  'apiPort': 'API port',
  'allowLan': 'Share on the LAN',
  'dns': 'DNS',
  'dnsRemote': 'Encrypted DNS (DoH)',
  'dnsIran': 'Iranian DNS (for .ir domains)',
  'dnsIpv4Only': 'IPv4 only',
  'dnsCache': 'DNS cache',
  'blockAds': 'Block ads',
  'blockQuic': 'Block QUIC (UDP/443)',
  'fragment': 'Packet fragmentation',
  'fragmentHint': 'Splits the TLS ClientHello to get past DPI boxes.',
  'fragmentLength': 'Fragment length',
  'fragmentInterval': 'Interval (ms)',
  'bypassIran': 'Bypass Iranian domains',
  'autoSelect': 'Auto select fastest server',
  'probeUrl': 'Probe URL',
  'muxEnabled': 'Mux (not recommended)',
  'customBypass': 'Direct domains',
  'customProxy': 'Proxied domains',
  'customRules': 'Custom rules (JSON)',
  'customRulesHint': 'An array of Xray routing rules, e.g.\n[{"type":"field","domain":["domain:example.com"],"outboundTag":"direct"}]',
  'tunName': 'Adapter name',
  'tunAddress': 'TUN address',
  'tunGateway': 'TUN gateway',
  'tunDns': 'TUN DNS',
  'tunAutoRoute': 'Automatic routing',
  'mtuLabel': 'MTU',
  'startMinimized': 'Start in tray',
  'closeToTray': 'Close to tray',
  'autoStart': 'Run at Windows startup',
  'autoConnect': 'Connect on launch',
  'autoReconnect': 'Reconnect automatically',
  'language': 'Language',
  'persian': 'فارسی',
  'english': 'English',
  'system': 'System',
  'theme': 'Theme',
  'themeLight': 'Light',
  'themeDark': 'Dark',
  'themeSystem': 'System',
  'openDataFolder': 'Settings folder',
  'openCoreFolder': 'Core folder',
  'openLogsFolder': 'Logs folder',
  'logLevel': 'Log level',
  'save': 'Save',
  'cancel': 'Cancel',
  'confirm': 'Confirm',
  'close': 'Close',
  'reset': 'Reset',
  'deleteTitle': 'Delete server',
  'deleteMessage': 'Are you sure you want to delete this server?',
  'adminRequiredTitle': 'Administrator rights required',
  'adminRequiredBody': 'TUN mode requires running the app as Administrator.',
  'ok': 'OK',
  'error': 'Error',
  'warning': 'Warning',
  'success': 'Done',
  'dismiss': 'Dismiss',
  'clearLogs': 'Clear logs',
  'logsEmpty': 'No log entries yet.',
  'version': 'Version',
  'build': 'Build',
  'osLabel': 'Operating system',
  'coreLabel': 'Core',
  'repository': 'Repository',
  'updateAvailable': 'A new version is available',
  'upToDate': 'You are up to date',
  'checkUpdate': 'Check for updates',
  'aboutBody': 'A light and fast V2Ray / Xray client with defaults tuned for Iranian networks. Supports Windows 7 through 11.',
};
