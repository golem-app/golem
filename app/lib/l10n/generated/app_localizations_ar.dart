// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'Golem';

  @override
  String get startingUp => 'جارٍ بدء التشغيل';

  @override
  String get launchTakingLonger => 'يستغرق بدء التشغيل وقتًا أطول من المتوقع.';

  @override
  String get launchStorageUnavailable =>
      'تعذر على Golem الوصول إلى مساحة التخزين على هذا الجهاز.';

  @override
  String get launchInvalidConfiguration =>
      'إعداد هذا الإصدار من Golem غير صحيح ولا يمكن تشغيله.';

  @override
  String get launchUnknownFailure => 'تعذر على Golem إكمال بدء التشغيل.';

  @override
  String get tryAgain => 'حاول مجددًا';

  @override
  String get back => 'رجوع';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get download => 'تنزيل';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get resume => 'استئناف';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get done => 'تم';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get chatTitle => 'المحادثة';

  @override
  String get settingsSectionModel => 'النموذج';

  @override
  String get settingsSectionApp => 'التطبيق';

  @override
  String get settingsSectionAbout => 'حول';

  @override
  String get settingsModel => 'النموذج';

  @override
  String get settingsResponseStyle => 'أسلوب الرد';

  @override
  String get settingsSystemPrompt => 'تعليمات النظام';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsPrivacyData => 'الخصوصية والبيانات';

  @override
  String get settingsStorage => 'مساحة التخزين';

  @override
  String get settingsBenchmark => 'اختبار الأداء';

  @override
  String get settingsModelAttribution => 'نَسب النماذج';

  @override
  String get settingsOpenSourceLicenses => 'تراخيص المصادر المفتوحة';

  @override
  String get settingsAboutGolem => 'حول Golem';

  @override
  String get languageSystem => 'لغة النظام';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePolish => 'Polski';

  @override
  String get languageSpanish => 'Español (Latinoamérica)';

  @override
  String get languageBrazilianPortuguese => 'Português (Brasil)';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageIndonesian => 'Bahasa Indonesia';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageVietnamese => 'Tiếng Việt';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageSystemDetail => 'استخدم اللغة المحددة لهذا الجهاز.';

  @override
  String get languageSaveFailed =>
      'تعذر حفظ اللغة. تمت استعادة اختيارك السابق.';

  @override
  String get preferencesLoadFailed => 'تعذر تحميل التفضيلات.';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get showInferenceMetrics => 'إظهار مقاييس التشغيل';

  @override
  String get alwaysExpandReasoning => 'توسيع التفكير دائمًا';

  @override
  String get hapticsOnSend => 'اهتزاز عند الإرسال';

  @override
  String get textSize => 'حجم النص';

  @override
  String get newChat => 'محادثة جديدة';

  @override
  String get searchChats => 'البحث في المحادثات';

  @override
  String get settings => 'الإعدادات';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get renameChat => 'إعادة تسمية المحادثة';

  @override
  String get shareTranscript => 'مشاركة نص المحادثة';

  @override
  String get pinToTop => 'تثبيت في الأعلى';

  @override
  String get unpin => 'إلغاء التثبيت';

  @override
  String get deleteChatTitle => 'هل تريد حذف المحادثة؟';

  @override
  String get deleteChatMessage => 'ستُزال هذه المحادثة من هذا الجهاز.';

  @override
  String get today => 'اليوم';

  @override
  String get yesterday => 'أمس';

  @override
  String get previousSevenDays => 'الأيام السبعة الماضية';

  @override
  String get older => 'أقدم';

  @override
  String get noChatsYet => 'لا توجد محادثات بعد';

  @override
  String get noSearchResults => 'لم يُعثر على محادثات';

  @override
  String get jumpToLatest => 'الانتقال إلى أحدث رسالة';

  @override
  String get messagePlaceholder => 'اكتب رسالة إلى Golem';

  @override
  String get sendMessage => 'إرسال الرسالة';

  @override
  String get stopGenerating => 'إيقاف الإنشاء';

  @override
  String get attach => 'إرفاق';

  @override
  String get copy => 'نسخ';

  @override
  String get copied => 'تم النسخ';

  @override
  String get reasoning => 'التفكير';

  @override
  String get showReasoning => 'إظهار التفكير';

  @override
  String get hideReasoning => 'إخفاء التفكير';

  @override
  String get thinking => 'جارٍ التفكير…';

  @override
  String get model => 'النموذج';

  @override
  String get models => 'النماذج';

  @override
  String get allModels => 'الكل';

  @override
  String get installedModels => 'المثبّتة';

  @override
  String get recommended => 'موصى به';

  @override
  String get activeModel => 'النموذج النشط';

  @override
  String get state => 'الحالة';

  @override
  String get revision => 'المراجعة';

  @override
  String get quantization => 'التكميم';

  @override
  String get size => 'الحجم';

  @override
  String get promptProfile => 'ملف التعليمات';

  @override
  String get repository => 'المستودع';

  @override
  String get context => 'السياق';

  @override
  String get input => 'الإدخال';

  @override
  String get textOnly => 'نص';

  @override
  String get textAndImages => 'نص وصور';

  @override
  String get downloadProgress => 'تقدم التنزيل';

  @override
  String get verifyingFiles => 'جارٍ التحقق من الملفات…';

  @override
  String get keep => 'إبقاء';

  @override
  String deleteModelTitle(String modelName) {
    return 'هل تريد حذف $modelName؟';
  }

  @override
  String get deleteModelMessage =>
      'ستُزال الملفات المنزلة من هذا الجهاز. يمكنك تنزيلها مجددًا لاحقًا.';

  @override
  String downloadSize(String size) {
    return 'تنزيل · $size';
  }

  @override
  String bytesDecimal(String value) {
    return '$value غيغابايت';
  }

  @override
  String chatCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محادثة',
      many: '$count محادثة',
      few: '$count محادثات',
      two: 'محادثتان',
      one: 'محادثة واحدة',
      zero: 'لا محادثات',
    );
    return '$_temp0';
  }

  @override
  String get defaultValue => 'افتراضي';

  @override
  String get customValue => 'مخصص';

  @override
  String get stylePrecise => 'دقيق';

  @override
  String get styleBalanced => 'متوازن';

  @override
  String get styleCreative => 'إبداعي';

  @override
  String get advancedMode => 'الوضع المتقدم';

  @override
  String get advancedModeDetail =>
      'عناصر تحكم أخذ العينات وتعليمات نظام مخصصة وإضافة أي مستودع Hugging Face يدويًا.';

  @override
  String get aboutLegal => 'حول التطبيق والمعلومات القانونية';

  @override
  String get openSourcePrivacyFootnote =>
      'Golem مفتوح المصدر. لا يرسل أي شيء من هذه الشاشة إلى أي مكان.';

  @override
  String get simulatedInferenceBanner => 'تشغيل محاكى · بلا تحقق من العتاد';

  @override
  String get theme => 'السمة';

  @override
  String get inTranscript => 'في نص المحادثة';

  @override
  String get textPreview => 'يبدو الحجم مناسبًا.';

  @override
  String percentValue(int value) {
    return '$value بالمئة';
  }

  @override
  String languageSelected(String language) {
    return 'تم تحديد $language';
  }

  @override
  String get modelDownloadsSimulated =>
      'تنزيل النماذج محاكاة حتمية للكتالوج المثبّت؛ ولا يوجد اتصال بالشبكة.';

  @override
  String get modelDownloadsReal =>
      'تجلب تنزيلات النماذج الملفات المثبّتة من Hugging Face عبر HTTPS.';

  @override
  String get inferenceSimulated =>
      'التشغيل محاكاة حتمية للواجهة، بلا أوزان نموذج أو محرك أو قياس للعتاد.';

  @override
  String get inferenceLocal =>
      'يعمل المحرك محليًا على هذا الجهاز باستخدام النموذج النشط.';

  @override
  String get networkPrivacyStatement =>
      'لا يستخدم أي شيء آخر الشبكة، ولا يقرأ Golem بيانات التطبيقات الأخرى.';

  @override
  String get saveFailed => 'تعذر الحفظ. حاول مجددًا.';

  @override
  String get firstRunTagline => 'تطبيق محادثة لا يرسل بياناتك إلى الخارج.';

  @override
  String get firstRunIntroduction =>
      'يحمّل Golem نموذجًا مفتوحًا واحدًا إلى هاتفك ويشغّله عليه. بلا حساب أو خادم أو نسخة من محادثاتك في مكان آخر.';

  @override
  String get promisePrivateTitle => 'لا شيء يغادر الجهاز';

  @override
  String get promisePrivateDetail => 'تُحفظ الرسائل في مساحة Golem الخاصة.';

  @override
  String get promiseOfflineTitle => 'يعمل بلا اتصال';

  @override
  String get promiseOfflineDetail => 'يكفي تنزيل النموذج مرة واحدة.';

  @override
  String get promiseControlTitle => 'كل عناصر التحكم عند الحاجة';

  @override
  String get promiseControlDetail =>
      'أسلوب الرد وتعليمات النظام وعناصر تحكم أخذ العينات.';

  @override
  String get getStarted => 'البدء';

  @override
  String get oneModelHeadline => 'نموذج واحد، بلا إعداد.';

  @override
  String get noCompatibleModel =>
      'لم يعثر Golem على نموذج متوافق في هذا الإصدار.';

  @override
  String modelOfflineIntroduction(String modelName) {
    return 'ينزّل Golem النموذج $modelName مرة واحدة، ثم لا يحتاج إلى الشبكة للإجابة في المحادثة.';
  }

  @override
  String get downloadUnavailable => 'التنزيل غير متاح';

  @override
  String get chooseDifferentModel => 'اختيار نموذج آخر';

  @override
  String tokensThousands(int count) {
    return '$count ألف رمز';
  }

  @override
  String get featuredModelDetail =>
      'مناسب للكتابة اليومية والملخصات والبرمجة الخفيفة. تعتمد سرعة النموذج على هذا الهاتف ولا تُقدّر قبل تشغيله.';

  @override
  String get allModelsTitle => 'كل النماذج';

  @override
  String get catalogSimulationDetail =>
      'يعرض إصدار QA هذا الكتالوج المثبّت كاملًا. تُحاكى التنزيلات وعمليات تشغيل النماذج.';

  @override
  String get catalogDeviceDetail =>
      'يمكن تحديد النماذج المتوافقة مع محرك هذا الإصدار. تحتاج النماذج الأكبر إلى فئة الأجهزة المفضلة.';

  @override
  String get chooseModel => 'اختيار نموذج';

  @override
  String get startChatting => 'بدء المحادثة';

  @override
  String get pauseDownload => 'إيقاف التنزيل مؤقتًا';

  @override
  String get retryDownload => 'إعادة محاولة التنزيل';

  @override
  String get resumeDownload => 'استئناف التنزيل';

  @override
  String modelReady(String modelName) {
    return 'النموذج $modelName جاهز';
  }

  @override
  String modelVerifying(String modelName) {
    return 'جارٍ التحقق من $modelName';
  }

  @override
  String get downloadPaused => 'التنزيل متوقف مؤقتًا';

  @override
  String get downloadNeedsAttention => 'التنزيل يحتاج إلى انتباه';

  @override
  String modelDownloading(String modelName) {
    return 'جارٍ تنزيل $modelName';
  }

  @override
  String get selectedCatalogUnavailable => 'عنصر الكتالوج المحدد غير متاح.';

  @override
  String get downloadFailed => 'فشل التنزيل. يمكنك المحاولة مجددًا.';

  @override
  String downloadInsufficientStorage(String required, String available) {
    return 'يحتاج النموذج إلى $required من المساحة الحرة، لكن المتاح $available فقط.';
  }

  @override
  String downloadHashVerificationFailed(String fileName) {
    return 'فشل الملف $fileName في التحقق من سلامته. أعد محاولة التنزيل.';
  }

  @override
  String downloadUnexpectedFileSize(String fileName) {
    return 'حجم الملف $fileName غير صحيح. أعد محاولة التنزيل.';
  }

  @override
  String get downloadSimulationComplete =>
      'اكتملت محاكاة QA الحتمية، ولم تُحفظ أي أوزان.';

  @override
  String get downloadComplete =>
      'تم التحقق على هذا الجهاز. يستطيع Golem الآن الإجابة بلا اتصال بالشبكة.';

  @override
  String downloadAmount(String downloaded, String total) {
    return '$downloaded من $total';
  }

  @override
  String downloadSimulationProgress(String amount) {
    return '$amount · محاكاة. لا يحدث طلب شبكة أو حفظ لأوزان النموذج.';
  }

  @override
  String downloadRealProgress(String amount) {
    return '$amount. اترك Golem مفتوحًا متى أمكن؛ فقد يواصل النظام النقل في الخلفية.';
  }

  @override
  String get chatsStayAvailable => 'تبقى المحادثات متاحة.';

  @override
  String get modelsUnavailableGeneric =>
      'لا يستطيع Golem تشغيل النماذج على هذا الجهاز.';

  @override
  String get unsupportedFeaturesRemain =>
      'لن يُنزّل أي نموذج. ما زال بإمكانك فتح المحادثات والسجل والإعدادات وعمليات التصدير.';

  @override
  String get continueToGolem => 'المتابعة إلى Golem';

  @override
  String get modelChoiceSaveFailed => 'تعذر حفظ اختيار النموذج. حاول مجددًا.';

  @override
  String get setupSaveFailed => 'تعذر على Golem حفظ الإعداد. حاول مجددًا.';

  @override
  String get simulateDownloadTitle => 'هل تريد محاكاة هذا التنزيل؟';

  @override
  String get downloadModelTitle => 'هل تريد تنزيل هذا النموذج؟';

  @override
  String simulateDownloadMessage(String modelName, String size) {
    return 'يظهر $modelName كتنزيل حجمه $size. لا تستخدم محاكاة QA هذه الشبكة ولا تحفظ أوزان النموذج.';
  }

  @override
  String downloadModelMessage(String modelName, String size) {
    return 'سينزّل $modelName مقدار $size من Hugging Face. أبقِ هذه المساحة و500 MiB إضافية فارغة. يُنصح باستخدام Wi-Fi؛ وقد تُطبق رسوم بيانات الجوال.';
  }

  @override
  String get notNow => 'ليس الآن';

  @override
  String get simulate => 'محاكاة';

  @override
  String finishModelSetup(String modelName) {
    return 'إكمال إعداد $modelName';
  }

  @override
  String modelDownloadPaused(String modelName) {
    return 'تنزيل $modelName متوقف مؤقتًا';
  }

  @override
  String modelNeedsAttention(String modelName) {
    return 'يحتاج $modelName إلى انتباه';
  }

  @override
  String get setupDownloadPrompt =>
      'نزّل النموذج المحدد وتحقق منه قبل استخدام Golem.';

  @override
  String get qaDownloadShort => 'محاكاة QA حتمية بلا شبكة أو أوزان.';

  @override
  String get downloadBeforeSending =>
      'يجب أن يكتمل تنزيل النموذج والتحقق منه قبل إرسال الرسائل.';

  @override
  String get resumeProgressKept =>
      'استأنف عندما تكون مستعدًا. تم الاحتفاظ بالتقدم الحالي.';

  @override
  String get checkingDownloadedFiles => 'جارٍ فحص الملفات المنزلة قبل تشغيلها.';

  @override
  String get downloadFailedChatsSafe => 'فشل التنزيل. لم تتأثر محادثاتك.';

  @override
  String get ready => 'جاهز.';

  @override
  String get conversationsAppearHere => 'ستظهر محادثاتك هنا.';

  @override
  String get pinned => 'مثبّت';

  @override
  String get unpinned => 'أُلغي التثبيت';

  @override
  String get earlier => 'سابقًا';

  @override
  String get conversationActions => 'إجراءات المحادثة';

  @override
  String deleteNamedChatMessage(String title) {
    return 'ستُزال «$title» وكل رسائلها من هذا الجهاز.';
  }

  @override
  String get chatDeleted => 'حُذفت المحادثة';

  @override
  String storageAmount(String used, String total) {
    return '$used من $total';
  }

  @override
  String get closeConversations => 'إغلاق قائمة المحادثات';

  @override
  String get discard => 'تجاهل';

  @override
  String downloadNamedModel(String modelName, String size) {
    return 'تنزيل $modelName ‏($size)';
  }

  @override
  String get addToChat => 'إضافة إلى هذه المحادثة';

  @override
  String get photoLibrary => 'مكتبة الصور';

  @override
  String get takePhoto => 'التقاط صورة';

  @override
  String get files => 'الملفات';

  @override
  String imagesPrivateDetail(String modelName) {
    return 'تُقرأ الصور على هذا الجهاز. يستطيع $modelName رؤيتها، ولا يُرفع أي شيء.';
  }

  @override
  String imagesUnsupportedDetail(String modelName) {
    return 'يتعامل $modelName مع النص فقط. انتقل إلى نموذج يقرأ الصور لإرفاق صورة.';
  }

  @override
  String get unsupportedImageType =>
      'نوع الملف هذا غير مدعوم. استخدم صورة JPEG أو PNG أو WebP.';

  @override
  String get imageTooLarge => 'هذه الصورة أكبر من أن تُرفق.';

  @override
  String get imageUnreadable => 'تعذرت قراءة هذه الصورة.';

  @override
  String get imagePermissionDenied =>
      'يحتاج Golem إلى الوصول إلى الكاميرا والصور. فعّل ذلك في الإعدادات لإرفاق صورة.';

  @override
  String get imageAddFailed => 'تعذرت إضافة هذه الصورة.';

  @override
  String get removeAttachedImage => 'إزالة الصورة المرفقة';

  @override
  String get modelForChat => 'نموذج هذه المحادثة';

  @override
  String get reasoningOn => 'التفكير مفعّل';

  @override
  String get reasoningOff => 'التفكير متوقف';

  @override
  String get think => 'فكّر';

  @override
  String get startPrivateConversation => 'بدء محادثة خاصة';

  @override
  String get whatAreWeBuilding => 'ماذا سنبني؟';

  @override
  String get cannotRunModelsHere => 'لا يستطيع Golem تشغيل النماذج هنا';

  @override
  String simulatedModelPrivacy(String modelName) {
    return 'تحاكي هذه المعاينة $modelName على هذا الهاتف. لا يذهب ما تكتبه هنا إلى أي مكان.';
  }

  @override
  String localModelPrivacy(String modelName) {
    return 'تم تحميل $modelName وهو يعمل على هذا الهاتف. لا يذهب ما تكتبه هنا إلى أي مكان.';
  }

  @override
  String downloadedModelPrivacy(String modelName) {
    return 'تم تنزيل $modelName والتحقق منه على هذا الهاتف. سيُحمّل عند إرسال رسالة. لا يذهب ما تكتبه هنا إلى أي مكان.';
  }

  @override
  String validatedModelPrivacy(String modelName) {
    return 'تم التحقق من $modelName لهذه الجلسة، ولا يعمل إلا على هذا الهاتف. لا يذهب ما تكتبه هنا إلى أي مكان.';
  }

  @override
  String get starterDraftReply => 'صياغة رد';

  @override
  String get starterDraftReplyPrompt => 'صُغ ردًا على هذه الرسالة: ';

  @override
  String get starterExplain => 'شرح موضوع';

  @override
  String get starterExplainPrompt => 'اشرح ببساطة: ';

  @override
  String get starterRewrite => 'إعادة صياغة نصي';

  @override
  String get starterRewritePrompt => 'أعد صياغة هذا النص ليصبح واضحًا: ';

  @override
  String get starterSummarise => 'تلخيص ملاحظة';

  @override
  String get starterSummarisePrompt => 'لخّص هذه الملاحظة: ';

  @override
  String get noChatsMatchSearch => 'لا توجد محادثات تطابق بحثك.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محادثة',
      many: '$count محادثة',
      few: '$count محادثات',
      two: 'محادثتان',
      one: 'محادثة واحدة',
      zero: 'لا محادثات',
    );
    return '$_temp0';
  }

  @override
  String get localSearchPrivacy =>
      'يبحث التطبيق في قاعدة البيانات المحلية. لا يُرفع أي فهرس.';

  @override
  String searchMatchSummary(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تطابق',
      many: '$count تطابقًا',
      few: '$count تطابقات',
      two: 'تطابقان',
      one: 'تطابق واحد',
      zero: 'لا تطابقات',
    );
    return '$date · $_temp0';
  }

  @override
  String stoppedAfterTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رمز',
      many: '$count رمزًا',
      few: '$count رموز',
      two: 'رمزين',
      one: 'رمز واحد',
      zero: '0 رمز',
    );
    return 'توقف بعد $_temp0';
  }

  @override
  String get copyMessage => 'نسخ الرسالة';

  @override
  String get regenerateResponse => 'إعادة إنشاء الرد';

  @override
  String get shareMessage => 'مشاركة الرسالة';

  @override
  String get messageActions => 'إجراءات الرسالة';

  @override
  String get regenerate => 'إعادة الإنشاء';

  @override
  String get branchFromHere => 'إنشاء فرع من هنا';

  @override
  String get share => 'مشاركة';

  @override
  String get deleteMessage => 'حذف الرسالة';

  @override
  String get copiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get newBranchStarted => 'بدأ فرع جديد';

  @override
  String get yourMessage => 'رسالتك';

  @override
  String get golemResponse => 'رد Golem';

  @override
  String get editAndRetry => 'تعديل وإعادة المحاولة';

  @override
  String get editMessage => 'تعديل الرسالة';

  @override
  String get userSpeaker => 'أنت';

  @override
  String get assistantSpeaker => 'Golem';

  @override
  String get saveAndRegenerate => 'حفظ وإعادة الإنشاء';

  @override
  String get generationFailed => 'حدث خطأ أثناء إنشاء الرد.';

  @override
  String get attachmentUnavailableFailure =>
      'لم تعد صورة في هذه المحادثة متاحة. احذف هذه الرسالة وأرسلها مجددًا.';

  @override
  String get modelUnavailableFailure =>
      'نموذج هذه المحادثة غير متاح في هذا الإصدار من Golem. اختر نموذجًا آخر للمتابعة.';

  @override
  String get unsupportedModelFailure =>
      'لا يستطيع Golem استخدام قالب المحادثة أو ملفات هذا النموذج. اختر نموذجًا مدعومًا للمتابعة.';

  @override
  String get unsupportedImagesFailure =>
      'لا يستطيع هذا النموذج قراءة الصورة في هذه الرسالة. احذف الرسالة أو اختر نموذجًا يقرأ الصور.';

  @override
  String get invalidModelArtifactFailure =>
      'النموذج المثبّت مفقود أو تالف أو غير متوافق مع هذا الإصدار من Golem. اختر نموذجًا آخر أو نزّله مجددًا.';

  @override
  String get attachmentSaveFailed =>
      'تعذر حفظ هذه الصورة. حاول إرفاقها مجددًا.';

  @override
  String modelMissingForChat(String modelName) {
    return 'لم يُنزّل $modelName على هذا الجهاز بعد. نزّله لاستخدامه في هذه المحادثة.';
  }

  @override
  String get contextExhausted =>
      'هذه المحادثة أطول من نافذة سياق النموذج. ابدأ محادثة جديدة للمتابعة.';

  @override
  String get outOfMemory =>
      'نفدت الذاكرة من النموذج أثناء الإنشاء. أغلق التطبيقات الأخرى وحاول مجددًا.';

  @override
  String get insufficientMemory =>
      'لا توجد ذاكرة حرة كافية لتحميل هذا النموذج. أغلق التطبيقات الأخرى أو اختر نموذجًا أصغر.';

  @override
  String get budgetExhausted =>
      'استخدم النموذج ميزانية الرموز قبل إنشاء رد. حاول مجددًا أو عدّل إعدادات الرد.';

  @override
  String imageCountSentence(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' $count صورة.',
      many: ' $count صورة.',
      few: ' $count صور.',
      two: ' صورتان.',
      one: ' صورة واحدة.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String tokenRateSummary(String rate, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رمز',
      many: '$count رمزًا',
      few: '$count رموز',
      two: 'رمزان',
      one: 'رمز واحد',
      zero: '0 رمز',
    );
    return '$rate رمز/ث · $_temp0';
  }

  @override
  String get aiDisclaimer =>
      'قد تكون ردود الذكاء الاصطناعي غير دقيقة. تحقق من المعلومات المهمة.';

  @override
  String get privacyStatement =>
      'يحافظ Golem على الخصوصية: لا يتطلب حسابًا ولا يرسل تحليلات، ويتوقف عن استخدام الشبكة بعد تنزيل النموذج. لا يوجد تتبع لتعطيله.';

  @override
  String get onThisPhone => 'على هذا الهاتف';

  @override
  String get saveChatHistory => 'حفظ سجل المحادثات';

  @override
  String get saveHistoryOffDetail =>
      'عند الإيقاف، تختفي كل محادثة عند إغلاق التطبيق.';

  @override
  String get yourData => 'بياناتك';

  @override
  String get exportAllChats => 'تصدير كل المحادثات';

  @override
  String get deleteAllChats => 'حذف كل المحادثات';

  @override
  String get stopSavingChatsTitle => 'هل تريد إيقاف حفظ المحادثات؟';

  @override
  String get stopSavingChatsMessage =>
      'ستُحذف الآن المحادثات المحفوظة على هذا الجهاز. تبقى المحادثات المفتوحة حتى إغلاق التطبيق، ولن تُكتب بيانات جديدة على القرص.';

  @override
  String get keepSaving => 'متابعة الحفظ';

  @override
  String get stopAndDelete => 'إيقاف وحذف';

  @override
  String get deleteSavedChatsFailed =>
      'تعذر حذف المحادثات المحفوظة. حاول مجددًا.';

  @override
  String get chatsExportSubject => 'تصدير محادثات Golem';

  @override
  String get deleteAllChatsTitle => 'هل تريد حذف كل المحادثات؟';

  @override
  String get deleteAllChatsMessage =>
      'ستُزال كل المحادثات من هذا الجهاز. ستبقى النماذج المنزلة.';

  @override
  String get chatsDeleted => 'حُذفت المحادثات';

  @override
  String get deleteChatsFailed => 'تعذر حذف المحادثات. حاول مجددًا.';

  @override
  String get systemPromptDetail =>
      'تعليمات ثابتة لكل رد جديد تُرسل قبل المحادثة. اتركها فارغة لاستخدام السلوك الافتراضي للنموذج.';

  @override
  String get systemPromptExample => 'مثال: أجب بإيجاز وبلغة بسيطة.';

  @override
  String get resetToDefault => 'إعادة إلى الافتراضي';

  @override
  String get systemPromptLocalFootnote =>
      'تنطبق التعليمات على كلا النموذجين وتبقى على هذا الجهاز.';

  @override
  String get storageReadFailed => 'تعذرت قراءة مساحة التخزين.';

  @override
  String get downloadedModels => 'النماذج المنزلة';

  @override
  String get clearInferenceCache => 'مسح ذاكرة التشغيل المؤقتة';

  @override
  String get modelDeletionFootnote =>
      'يؤدي حذف نموذج إلى تحرير المساحة فورًا. تبقى محادثاتك محفوظة.';

  @override
  String get cacheCleared => 'مُسحت الذاكرة المؤقتة';

  @override
  String storageFree(String size) {
    return 'المتاح $size';
  }

  @override
  String storageModelsAmount(String size) {
    return 'النماذج $size';
  }

  @override
  String storageChatsAmount(String size) {
    return 'المحادثات $size';
  }

  @override
  String storageImagesAmount(String size) {
    return 'الصور $size';
  }

  @override
  String storageCacheAmount(String size) {
    return 'الذاكرة المؤقتة $size';
  }

  @override
  String get noDownloadedModels => 'لا توجد نماذج منزلة بعد.';

  @override
  String get active => 'نشط';

  @override
  String get partial => 'جزئي';

  @override
  String deleteModelArtifactTitle(String modelName, String format) {
    return 'هل تريد حذف $modelName · $format؟';
  }

  @override
  String deleteModelStorageMessage(String size) {
    return 'يزيل $size من هذا الجهاز. يمكن تنزيل النموذج مجددًا لاحقًا.';
  }

  @override
  String megabytes(int value) {
    return '$value ميغابايت';
  }

  @override
  String get licensesIntroduction =>
      'بُني Golem باستخدام برمجيات مفتوحة المصدر. تتوفر هذه الإشعارات بلا اتصال وتشمل تراخيص Dart والمحرك الأصلي والنماذج المستخدمة في هذا الإصدار.';

  @override
  String licenseEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بند ترخيص',
      many: '$count بند ترخيص',
      few: '$count بنود ترخيص',
      two: 'بندا ترخيص',
      one: 'بند ترخيص واحد',
      zero: 'لا بنود ترخيص',
    );
    return '$_temp0';
  }

  @override
  String get licensesLoadFailed => 'تعذر تحميل التراخيص.';

  @override
  String get licensesRetryDetail =>
      'لا تزال الملفات المضمنة على هذا الجهاز. حاول تحميلها مجددًا.';

  @override
  String showLicenseFor(String name) {
    return 'إظهار ترخيص $name';
  }

  @override
  String hideLicenseFor(String name) {
    return 'إخفاء ترخيص $name';
  }

  @override
  String get modelAttributionIntroduction =>
      'لا يتضمن Golem أوزان النماذج. لا ينزّل الملفات المحددة هنا إلا بعد موافقتك.';

  @override
  String get officialModelCard => 'بطاقة النموذج الرسمية';

  @override
  String get license => 'الترخيص';

  @override
  String get customRepositoryTerms =>
      'تخضع المستودعات المضافة يدويًا لشروط مصادرها. لا يعتمدها Golem ولا يعيد توزيعها.';

  @override
  String get startupFailed => 'فشل بدء التشغيل';

  @override
  String get startupCouldNotFinish => 'تعذر على Golem إكمال بدء التشغيل';

  @override
  String get preparingFirstRun => 'جارٍ إعداد التشغيل الأول';

  @override
  String get preparingSetup => 'جارٍ تحضير الإعداد';

  @override
  String get startingOnDevice => 'جارٍ تشغيل Golem على هذا الجهاز';

  @override
  String get gettingReady => 'جارٍ التحضير';

  @override
  String get splashTagline => 'خاص ومحلي وجاهز دائمًا.';

  @override
  String get chatHistoryNotSaving =>
      'لا يُحفظ سجل المحادثات. قد تُفقد آخر تغييراتك عند إغلاق التطبيق.';

  @override
  String get saving => 'جارٍ الحفظ…';

  @override
  String get reasoningLive => 'تفكير مباشر';

  @override
  String get expanded => 'موسّع';

  @override
  String get collapsed => 'مطوي';

  @override
  String get reasoningLiveBadge => 'التفكير · مباشر';

  @override
  String generatingAtRate(String rate) {
    return 'جارٍ الإنشاء · $rate رمز/ث';
  }

  @override
  String get imageUnavailable => 'لم تعد الصورة متاحة';

  @override
  String get loadingImage => 'جارٍ تحميل الصورة';

  @override
  String get golemResponding => 'يجيب Golem';

  @override
  String get responseFinished => 'اكتمل الرد';

  @override
  String get chatHistoryLoadFailed => 'تعذر تحميل سجل المحادثات.';

  @override
  String get openConversations => 'فتح المحادثات';

  @override
  String get images => 'الصور';

  @override
  String get stop => 'إيقاف';

  @override
  String get send => 'إرسال';

  @override
  String get copyCode => 'نسخ الكود';

  @override
  String get code => 'كود';

  @override
  String get unsupportedDevice => 'جهاز غير مدعوم';

  @override
  String get simulated => 'محاكاة';

  @override
  String get onDevice => 'على الجهاز';

  @override
  String get responseStyle => 'أسلوب الرد';

  @override
  String responseStyleDescription(String modelName) {
    return 'مقدار الحرية المتاحة لـ $modelName في الارتجال. لا يؤثر هذا إلا في الردود الجديدة.';
  }

  @override
  String get advancedSamplingHint =>
      'فعّل الوضع المتقدم في الإعدادات لضبط الحرارة وtop-p وميزانيات الرموز يدويًا.';

  @override
  String get sampling => 'أخذ العينات';

  @override
  String get stylePreciseDetail => 'يلتزم بالحقائق. الأفضل للكود والملخصات.';

  @override
  String get styleBalancedDetail => 'إعدادات النموذج الافتراضية. موصى به.';

  @override
  String get styleCreativeDetail => 'أكثر حرية وتنوعًا. قد يخطئ أحيانًا.';

  @override
  String selectedOption(String name) {
    return 'تم تحديد $name';
  }

  @override
  String get noTunableProfile =>
      'لا يملك هذا النموذج ملفًا قابلًا للضبط في هذا الإصدار.';

  @override
  String get settingsLoadFailed => 'تعذر تحميل الإعدادات.';

  @override
  String get samplingTemperature => 'الحرارة';

  @override
  String get samplingTopP => 'Top-p';

  @override
  String get samplingTopK => 'Top-k';

  @override
  String get off => 'متوقف';

  @override
  String get maxTokens => 'الحد الأقصى للرموز';

  @override
  String get contextLength => 'طول السياق';

  @override
  String styleSource(String style) {
    return '· $style';
  }

  @override
  String get defaultSource => '· افتراضي';

  @override
  String get tokenBudgetFootnote =>
      'تترك ميزانيات الرموز دائمًا 512 رمزًا من السياق للتعليمات.';

  @override
  String get pinnedTokenBudgetFootnote =>
      'تترك ميزانيات الرموز دائمًا 512 رمزًا من السياق للتعليمات. يحتفظ وضع التفكير بإعدادات أخذ العينات المثبّتة لهذا النموذج، وتنطبق الميزانيات على كلا الوضعين.';

  @override
  String get modelsLoadFailed => 'تعذر تحميل حالة النماذج.';

  @override
  String get modelRuntimeFailed =>
      'توقف وقت تشغيل النموذج على نحو غير متوقع. حاول تحميله مجددًا.';

  @override
  String get nothingInstalled => 'لم يُثبّت أي شيء بعد.';

  @override
  String get nothingInstalledSimulated =>
      'لم يُثبّت أي شيء بعد. التنزيلات هنا محاكاة حتمية.';

  @override
  String get runtime => 'وقت التشغيل';

  @override
  String get customRepository => 'مستودع مخصص';

  @override
  String get none => 'لا شيء';

  @override
  String get noneSimulatedInference => 'لا شيء · تشغيل محاكى';

  @override
  String get unloadRuntime => 'إلغاء تحميل وقت التشغيل';

  @override
  String get loadRuntime => 'تحميل وقت التشغيل';

  @override
  String get unloadSimulatedRuntime => 'إلغاء تحميل وقت التشغيل المحاكى';

  @override
  String get loadSimulatedRuntime => 'تحميل وقت التشغيل المحاكى';

  @override
  String get modelSaveFailed => 'تعذر حفظ النموذج. حاول مجددًا.';

  @override
  String get modelAdded => 'تمت إضافة النموذج';

  @override
  String get repositoryMalformedIdentifier =>
      'أدخل مستودعًا عامًا بصيغة owner/name، مثل unsloth/gemma-4-E2B-it-qat-GGUF.';

  @override
  String get repositoryNotFoundOrPrivate =>
      'تعذرت قراءة هذا المستودع. تحقق من الاسم؛ فالمستودعات الخاصة غير مدعومة.';

  @override
  String get repositoryGated =>
      'يتطلب هذا المستودع قبول ترخيصه على Hugging Face. المستودعات المقيّدة غير مدعومة.';

  @override
  String get repositoryDisabled => 'تم تعطيل هذا المستودع على Hugging Face.';

  @override
  String get repositoryRateLimited =>
      'يفرض Hugging Face حدًا لمعدل الطلبات من هذا الجهاز. حاول مجددًا بعد قليل.';

  @override
  String get repositoryNetwork =>
      'تعذر الوصول إلى Hugging Face. تحقق من اتصالك وحاول مجددًا.';

  @override
  String get repositoryMalformedMetadata =>
      'أعاد Hugging Face بيانات غير متوقعة لهذا المستودع. حاول مجددًا بعد قليل.';

  @override
  String get repositoryUnsafePath =>
      'يحتوي هذا المستودع على مسار ملف لن يكتبه التطبيق.';

  @override
  String get repositoryNoWeights =>
      'لم يُعثر في هذا المستودع على أوزان يستطيع هذا المحرك تحميلها.';

  @override
  String get repositoryShardedWeights =>
      'هذا النموذج مقسّم بين عدة ملفات أوزان، وهو غير مدعوم بعد. اختر إصدارًا بملف واحد.';

  @override
  String get repositoryUnsafeWeightFormat =>
      'ينشر هذا المستودع أوزانه بصيغة لن يحمّلها التطبيق. لا تُدعم إلا safetensors وGGUF.';

  @override
  String get repositoryMissingRequiredFile =>
      'يفتقد هذا المستودع ملفات يحتاج إليها المحرك لتحميله.';

  @override
  String get repositoryInconsistentMetadata =>
      'تتعارض قائمة ملفات هذا المستودع مع نفسها، لذلك لا يمكن تثبيته بأمان.';

  @override
  String get repositoryUnsupportedArchitecture =>
      'لا يستطيع هذا الإصدار من Golem تشغيل بنية هذا النموذج.';

  @override
  String get repositoryHeaderTooLarge =>
      'بيانات هذا النموذج الوصفية أكبر مما يستطيع التطبيق قراءته.';

  @override
  String get repositoryDuplicateEntry => 'أُضيف هذا المستودع من قبل.';

  @override
  String get repositoryRevisionPlaceholder => 'main — أو فرع أو وسم أو commit';

  @override
  String get unknownTemplateWarning =>
      'سيُنزّل هذا النموذج ويمكن حذفه، لكن Golem لا يستطيع إرسال تعليمات إليه لأن قالب محادثته غير معروف لهذا الإصدار.';

  @override
  String get simulatedRepositoryDetail =>
      'يحاكي هذا الإصدار التنزيلات، لذا تُنشأ بيانات المراجعة والحجم أدناه بدل قراءتها من Hugging Face.';

  @override
  String get publicRepositoryDetail =>
      'لا تُدعم إلا المستودعات العامة. لن يبدأ التنزيل قبل عرض نتيجة الفحص.';

  @override
  String get readingRepository => 'جارٍ قراءة المستودع…';

  @override
  String get chooseWeightFile =>
      'يحتوي هذا المستودع على عدة ملفات أوزان. اختر الملف المراد تثبيته:';

  @override
  String get notRecognized => 'غير معروف';

  @override
  String moreFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف إضافي',
      many: '$count ملفًا إضافيًا',
      few: '$count ملفات إضافية',
      two: 'ملفان إضافيان',
      one: 'ملف إضافي واحد',
      zero: 'لا ملفات إضافية',
    );
    return '+ $_temp0';
  }

  @override
  String get addModel => 'إضافة نموذج';

  @override
  String get resolveRepository => 'فحص';

  @override
  String get activeBadge => 'محدد';

  @override
  String get loadedBadge => 'محمّل';

  @override
  String modelStatusLabel(String modelName, String engine) {
    return 'حالة النموذج $modelName ‏($engine)';
  }

  @override
  String downloadProgressLabel(String suffix) {
    return 'التنزيل$suffix';
  }

  @override
  String verifyingFilesStatus(String suffix) {
    return 'جارٍ التحقق من الملفات$suffix…';
  }

  @override
  String openRepository(String repository) {
    return 'فتح $repository على Hugging Face';
  }

  @override
  String modelSizeAndFiles(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف',
      many: '$count ملفًا',
      few: '$count ملفات',
      two: 'ملفان',
      one: 'ملف واحد',
      zero: 'لا ملفات',
    );
    return '$size · $_temp0';
  }

  @override
  String measuredSimulated(String rate) {
    return '$rate رمز/ث · محاكاة';
  }

  @override
  String measuredOnPhone(String rate) {
    return '$rate رمز/ث على هذا الهاتف';
  }

  @override
  String get measured => 'مقاس';

  @override
  String downloadSizeAction(String size) {
    return 'تنزيل · $size';
  }

  @override
  String get cancelAndDiscard => 'إلغاء وتجاهل';

  @override
  String get deleteDownload => 'حذف التنزيل';

  @override
  String get notDownloaded => 'غير منزّل';

  @override
  String downloadingAmountStatus(
    String downloaded,
    String total,
    String suffix,
  ) {
    return 'جارٍ تنزيل $downloaded من $total$suffix';
  }

  @override
  String pausedAtStatus(String downloaded, String suffix) {
    return 'متوقف مؤقتًا عند $downloaded$suffix';
  }

  @override
  String verifyingStatus(String suffix) {
    return 'جارٍ التحقق$suffix';
  }

  @override
  String installedVerifiedStatus(String suffix) {
    return 'مثبّت وتم التحقق منه$suffix';
  }

  @override
  String get unloaded => 'غير محمّل';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get loadingSimulation => 'جارٍ تحميل المحاكاة…';

  @override
  String get readySimulated => 'جاهز · محاكاة';

  @override
  String get stopped => 'متوقف';

  @override
  String get benchmark => 'اختبار الأداء';

  @override
  String get protocol => 'البروتوكول';

  @override
  String get prompt => 'التعليمات';

  @override
  String get run => 'التشغيل';

  @override
  String get warmup => 'الإحماء';

  @override
  String get maximumOutput => 'أقصى مخرجات';

  @override
  String get seed => 'البذرة';

  @override
  String get benchmarkProtocolDetail =>
      'يستخدم ملف تعليمات الإنتاج المتتبع. المخرجات والتوقيت محاكاة حتمية فقط.';

  @override
  String get simulationStatus => 'حالة المحاكاة';

  @override
  String get thermal => 'الحالة الحرارية';

  @override
  String get notMeasured => 'غير مقاس';

  @override
  String get lowPowerMode => 'وضع الطاقة المنخفضة';

  @override
  String get notRead => 'غير مقروء';

  @override
  String get hardwareValidation => 'التحقق من العتاد';

  @override
  String get no => 'لا';

  @override
  String get stopSimulatedBenchmark => 'إيقاف اختبار الأداء المحاكى';

  @override
  String get runSimulatedBenchmark => 'تشغيل اختبار الأداء المحاكى';

  @override
  String get generatingDeterministicResult => 'جارٍ إنشاء نتيجة حتمية…';

  @override
  String get simulatedResult => 'نتيجة المحاكاة';

  @override
  String get benchmarkPrompt => 'تعليمات اختبار الأداء';

  @override
  String get shortExplanation => 'شرح قصير';

  @override
  String get mediumReview => 'مراجعة متوسطة';

  @override
  String get longSynthesis => 'تركيب مطوّل';

  @override
  String get simulatedNotValidated => 'محاكاة · بلا تحقق من العتاد';

  @override
  String get generated => 'تم الإنشاء';

  @override
  String tokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رمز',
      many: '$count رمزًا',
      few: '$count رموز',
      two: 'رمزان',
      one: 'رمز واحد',
      zero: '0 رمز',
    );
    return '$_temp0';
  }

  @override
  String get decode => 'فك الترميز';

  @override
  String tokenRate(String rate) {
    return '$rate رمز/ث';
  }

  @override
  String get peakMemory => 'ذروة استخدام الذاكرة';

  @override
  String get simulatedEndOfTurn => 'نهاية رد محاكاة';

  @override
  String get benchmarkExportTitle => 'اختبار أداء Golem المحاكى';

  @override
  String get benchmarkExportText =>
      'ملف JSON لاختبار أداء محاكى، بلا تحقق من العتاد.';

  @override
  String get exportSimulatedJson => 'تصدير JSON المحاكى';

  @override
  String get benchmarkSimulationNotice =>
      'تحاكي هذه الشاشة سير العمل. ولا تقيس أداء هذا الجهاز.';

  @override
  String get deviceMissingInstructionSet =>
      'يفتقد معالج هذا الجهاز مجموعة تعليمات يحتاج إليها المحرك المحلي، لذلك لا يمكنه تشغيل النماذج هنا.';

  @override
  String get deviceBelowMemoryFloor =>
      'ذاكرة هذا الجهاز أقل مما يحتاج إليه أصغر نموذج يقدمه Golem، لذا عُطّلت التنزيلات هنا. لم تتأثر محادثاتك أو إعداداتك.';

  @override
  String outOfMemoryAtContext(int tokens) {
    final intl.NumberFormat tokensNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String tokensString = tokensNumberFormat.format(tokens);

    return 'نفدت الذاكرة عند $tokensString رمز. خفّض طول السياق أو اختر نموذجًا أصغر.';
  }

  @override
  String get defaultLowercase => 'افتراضي';

  @override
  String get stylePreciseLowercase => 'دقيق';

  @override
  String get styleBalancedLowercase => 'متوازن';

  @override
  String get styleCreativeLowercase => 'إبداعي';

  @override
  String hiddenEngineModels(int count, String engine) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نموذج آخر مصمم لمحرك مختلف ولا يظهر في القائمة.',
      many: '$count نموذجًا آخر مصممًا لمحرك مختلف ولا يظهر في القائمة.',
      few: '$count نماذج أخرى مصممة لمحرك مختلف ولا تظهر في القائمة.',
      two: 'نموذجان آخران مصممان لمحرك مختلف ولا يظهران في القائمة.',
      one: 'نموذج آخر مصمم لمحرك مختلف ولا يظهر في القائمة.',
      zero: 'لا نماذج أخرى مخفية.',
    );
    return '$_temp0 يشغّل هذا الإصدار المحرك $engine.';
  }

  @override
  String get notAvailableOnDevice => 'غير متاح على هذا الجهاز.';

  @override
  String get pinnedByBuild => 'مثبّت بواسطة هذا الإصدار.';

  @override
  String otherEngineAdmission(String engine) {
    return 'يستخدم هذا الإصدار المحرك $engine.';
  }

  @override
  String get memoryUnreadableLighterModel =>
      'تعذر على Golem قراءة ذاكرة هذا الهاتف، لذلك يقدّم النموذج الأخف هنا.';

  @override
  String get needsMoreReportedMemory =>
      'يحتاج إلى ذاكرة أكبر مما يبلّغ عنه هذا الهاتف.';

  @override
  String get modelsUnavailableOnDevice => 'النماذج غير متاحة على هذا الجهاز.';

  @override
  String get unresolvedRepositoryReason =>
      'لم يُفحص هذا المستودع في Hugging Face، لذلك ملفاته غير معروفة. أضفه مجددًا لفحصه.';

  @override
  String installedOtherEngine(String buildEngine, String modelEngine) {
    return 'مثبّت، لكن هذا الإصدار يشغّل $buildEngine ولا يستطيع تحميل نماذج $modelEngine.';
  }

  @override
  String get unrecognizedChatTemplate =>
      'مثبّت، لكن Golem لا يتعرف على قالب محادثة هذا النموذج، لذلك لا يستطيع إرسال تعليمات إليه.';

  @override
  String get pickAfterDownload => 'يمكن اختياره بعد اكتمال التنزيل.';

  @override
  String get resumeForChat => 'استأنف التنزيل لاستخدامه في هذه المحادثة.';

  @override
  String get unfinishedDownload =>
      'لم يكتمل التنزيل، لذلك لا يمكن اختياره بعد.';

  @override
  String get downloadForChat => 'نزّله لاستخدامه في هذه المحادثة.';

  @override
  String get customModelSummary => 'أضفته من Hugging Face.';

  @override
  String get anotherModelDownloading => 'يجري تنزيل نموذج آخر.';

  @override
  String downloadingStatus(String suffix) {
    return 'جارٍ التنزيل$suffix';
  }

  @override
  String verifyingFilesPicker(String suffix) {
    return 'جارٍ التحقق من الملفات$suffix';
  }

  @override
  String pausedDownloadAmount(String downloaded, String total, String suffix) {
    return 'متوقف مؤقتًا عند $downloaded من $total$suffix.';
  }

  @override
  String get readsPictures => 'يقرأ الصور';

  @override
  String modelSpeedSimulated(String rate) {
    return '$rate رمز/ث · محاكاة';
  }

  @override
  String modelSpeedOnPhone(String rate) {
    return '$rate رمز/ث على هذا الهاتف';
  }

  @override
  String get buildDefaultModel => 'النموذج الافتراضي لهذا الإصدار.';

  @override
  String get lighterModelUnknownMemory =>
      'النموذج الأخف، اختير لتعذر قراءة ذاكرة هذا الهاتف.';

  @override
  String get largerModelFits => 'يملك هذا الهاتف ذاكرة تكفي للنموذج الأكبر.';

  @override
  String get sizedForPhone => 'حجمه ملائم لذاكرة هذا الهاتف.';

  @override
  String sideloadPreventsSwitch(String modelName) {
    return 'يشغّل هذا الإصدار $modelName من مسار مثبّت، لذلك لا يمكن لهذه المحادثة تبديل النماذج.';
  }

  @override
  String get modelLoadsNextMessage =>
      'سيُحمّل النموذج الذي تختاره مع رسالتك التالية.';

  @override
  String get selectedModel => 'النموذج المحدد';

  @override
  String get manageModels => 'إدارة النماذج';

  @override
  String get gemmaModelSummary =>
      'نموذج متوازن متعدد الاستخدامات للكتابة اليومية والتلخيص والبرمجة الخفيفة.';

  @override
  String get qwenTwoBModelSummary =>
      'الأصغر والأسرع في الإجابة. الأفضل للأسئلة القصيرة والهواتف ذات الذاكرة الحرة الأقل.';

  @override
  String get qwenFourBModelSummary =>
      'يميل إلى البرمجة والرياضيات، ويمكنه التفكير في المسألة قبل الإجابة.';
}
