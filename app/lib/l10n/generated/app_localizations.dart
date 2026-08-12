import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('ko'),
    Locale('pl'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('tr'),
    Locale('vi'),
  ];

  /// Product name used in accessibility labels.
  ///
  /// In en, this message translates to:
  /// **'Golem'**
  String get appName;

  /// Bootstrap progress caption.
  ///
  /// In en, this message translates to:
  /// **'Starting up'**
  String get startingUp;

  /// Bootstrap timeout message.
  ///
  /// In en, this message translates to:
  /// **'Starting is taking longer than expected.'**
  String get launchTakingLonger;

  /// Bootstrap storage failure.
  ///
  /// In en, this message translates to:
  /// **'Golem could not access its storage on this device.'**
  String get launchStorageUnavailable;

  /// Bootstrap configuration failure.
  ///
  /// In en, this message translates to:
  /// **'This build of Golem is misconfigured and cannot start.'**
  String get launchInvalidConfiguration;

  /// Generic bootstrap failure.
  ///
  /// In en, this message translates to:
  /// **'Golem could not finish starting.'**
  String get launchUnknownFailure;

  /// Generic retry action.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Back navigation accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Generic cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic save action.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic download action.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// Generic pause action.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Generic resume action.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// Generic retry label.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic reset label.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Generic completion label.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Settings screen title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Chat screen and previous-page title.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// Model settings section heading.
  ///
  /// In en, this message translates to:
  /// **'MODEL'**
  String get settingsSectionModel;

  /// App settings section heading.
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get settingsSectionApp;

  /// About settings section heading.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get settingsSectionAbout;

  /// Model settings row.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsModel;

  /// Response style settings row.
  ///
  /// In en, this message translates to:
  /// **'Response style'**
  String get settingsResponseStyle;

  /// System prompt settings row.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get settingsSystemPrompt;

  /// Appearance settings row.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Language settings row and screen title.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Privacy settings row.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data'**
  String get settingsPrivacyData;

  /// Storage settings row.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// Benchmark settings row.
  ///
  /// In en, this message translates to:
  /// **'Benchmark'**
  String get settingsBenchmark;

  /// Model attribution settings row.
  ///
  /// In en, this message translates to:
  /// **'Model attribution'**
  String get settingsModelAttribution;

  /// Open-source license settings row.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get settingsOpenSourceLicenses;

  /// About Golem settings row and sheet title.
  ///
  /// In en, this message translates to:
  /// **'About Golem'**
  String get settingsAboutGolem;

  /// Follow the device language.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// English language endonym.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Polish language endonym.
  ///
  /// In en, this message translates to:
  /// **'Polski'**
  String get languagePolish;

  /// Neutral Latin American Spanish language endonym.
  ///
  /// In en, this message translates to:
  /// **'Español (Latinoamérica)'**
  String get languageSpanish;

  /// Brazilian Portuguese language endonym.
  ///
  /// In en, this message translates to:
  /// **'Português (Brasil)'**
  String get languageBrazilianPortuguese;

  /// Japanese language endonym.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get languageJapanese;

  /// Indonesian language endonym.
  ///
  /// In en, this message translates to:
  /// **'Bahasa Indonesia'**
  String get languageIndonesian;

  /// Hindi language endonym.
  ///
  /// In en, this message translates to:
  /// **'हिन्दी'**
  String get languageHindi;

  /// French language endonym.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// Vietnamese language endonym.
  ///
  /// In en, this message translates to:
  /// **'Tiếng Việt'**
  String get languageVietnamese;

  /// Turkish language endonym.
  ///
  /// In en, this message translates to:
  /// **'Türkçe'**
  String get languageTurkish;

  /// Korean language endonym.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get languageKorean;

  /// Arabic language endonym.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// System-language choice explanation.
  ///
  /// In en, this message translates to:
  /// **'Use the language selected for this device.'**
  String get languageSystemDetail;

  /// Language preference save failure.
  ///
  /// In en, this message translates to:
  /// **'The language could not be saved. Your previous choice was restored.'**
  String get languageSaveFailed;

  /// Preferences load failure.
  ///
  /// In en, this message translates to:
  /// **'Could not load preferences.'**
  String get preferencesLoadFailed;

  /// Follow system appearance.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Light appearance.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Dark appearance.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Appearance toggle.
  ///
  /// In en, this message translates to:
  /// **'Show inference metrics'**
  String get showInferenceMetrics;

  /// Appearance toggle.
  ///
  /// In en, this message translates to:
  /// **'Always expand reasoning'**
  String get alwaysExpandReasoning;

  /// Appearance toggle.
  ///
  /// In en, this message translates to:
  /// **'Haptics on send'**
  String get hapticsOnSend;

  /// Text size control label.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// Untitled conversation label and action.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// Conversation search title and field label.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get searchChats;

  /// Settings navigation action.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Rename conversation action.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Rename conversation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Rename chat'**
  String get renameChat;

  /// Share conversation action.
  ///
  /// In en, this message translates to:
  /// **'Share transcript'**
  String get shareTranscript;

  /// Pin conversation action.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get pinToTop;

  /// Unpin conversation action.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// Delete conversation confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get deleteChatTitle;

  /// Delete conversation confirmation message.
  ///
  /// In en, this message translates to:
  /// **'This chat will be removed from this device.'**
  String get deleteChatMessage;

  /// Current-day conversation section.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Previous-day conversation section.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Recent conversation section.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 days'**
  String get previousSevenDays;

  /// Older conversation section.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get older;

  /// Empty conversation history.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// Empty conversation search results.
  ///
  /// In en, this message translates to:
  /// **'No chats found'**
  String get noSearchResults;

  /// Chat scroll action accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest message'**
  String get jumpToLatest;

  /// Chat composer placeholder.
  ///
  /// In en, this message translates to:
  /// **'Message Golem'**
  String get messagePlaceholder;

  /// Chat composer send accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// Chat composer stop accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get stopGenerating;

  /// Attachment action.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attach;

  /// Copy content action.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Copy success toast.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// Model reasoning disclosure label.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get reasoning;

  /// Expand reasoning action.
  ///
  /// In en, this message translates to:
  /// **'Show reasoning'**
  String get showReasoning;

  /// Collapse reasoning action.
  ///
  /// In en, this message translates to:
  /// **'Hide reasoning'**
  String get hideReasoning;

  /// Inference progress state.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get thinking;

  /// Generic model label.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// Models screen title.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// All-models catalog tab.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allModels;

  /// Installed-models catalog tab.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installedModels;

  /// Recommended model badge.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get recommended;

  /// Active model label.
  ///
  /// In en, this message translates to:
  /// **'Active model'**
  String get activeModel;

  /// Model state label.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get state;

  /// Model repository revision label.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get revision;

  /// Model quantization label.
  ///
  /// In en, this message translates to:
  /// **'Quantization'**
  String get quantization;

  /// Model size label.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// Model prompt profile label.
  ///
  /// In en, this message translates to:
  /// **'Prompt profile'**
  String get promptProfile;

  /// Model repository label.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get repository;

  /// Model context window label.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get context;

  /// Model input capabilities label.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get input;

  /// Text-only model capability.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textOnly;

  /// Multimodal model capability.
  ///
  /// In en, this message translates to:
  /// **'Text + images'**
  String get textAndImages;

  /// Download progress accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Download progress'**
  String get downloadProgress;

  /// Model verification status.
  ///
  /// In en, this message translates to:
  /// **'Verifying files…'**
  String get verifyingFiles;

  /// Keep model action.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// Delete model confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete {modelName}?'**
  String deleteModelTitle(String modelName);

  /// Delete model confirmation body.
  ///
  /// In en, this message translates to:
  /// **'The downloaded files will be removed from this device. You can download them again later.'**
  String get deleteModelMessage;

  /// Download action with size.
  ///
  /// In en, this message translates to:
  /// **'Download · {size}'**
  String downloadSize(String size);

  /// Decimal gigabyte value.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String bytesDecimal(String value);

  /// Number of chats.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No chats} =1{1 chat} other{{count} chats}}'**
  String chatCount(int count);

  /// Default setting value.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultValue;

  /// Custom setting value.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customValue;

  /// Precise response style.
  ///
  /// In en, this message translates to:
  /// **'Precise'**
  String get stylePrecise;

  /// Balanced response style.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get styleBalanced;

  /// Creative response style.
  ///
  /// In en, this message translates to:
  /// **'Creative'**
  String get styleCreative;

  /// Advanced settings toggle.
  ///
  /// In en, this message translates to:
  /// **'Advanced mode'**
  String get advancedMode;

  /// Advanced mode explanation.
  ///
  /// In en, this message translates to:
  /// **'Sampling controls, a custom system prompt, and loading any Hugging Face repository by hand.'**
  String get advancedModeDetail;

  /// About and legal section heading.
  ///
  /// In en, this message translates to:
  /// **'About & legal'**
  String get aboutLegal;

  /// Settings privacy footnote.
  ///
  /// In en, this message translates to:
  /// **'Golem is open source. Nothing on this screen sends anything anywhere.'**
  String get openSourcePrivacyFootnote;

  /// QA simulation honesty banner.
  ///
  /// In en, this message translates to:
  /// **'SIMULATED INFERENCE · No hardware validation'**
  String get simulatedInferenceBanner;

  /// Appearance theme section.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Transcript appearance section.
  ///
  /// In en, this message translates to:
  /// **'In the transcript'**
  String get inTranscript;

  /// Text-size preview message.
  ///
  /// In en, this message translates to:
  /// **'Looks about right.'**
  String get textPreview;

  /// Accessible percentage value.
  ///
  /// In en, this message translates to:
  /// **'{value} percent'**
  String percentValue(int value);

  /// Selected language accessibility value.
  ///
  /// In en, this message translates to:
  /// **'{language} selected'**
  String languageSelected(String language);

  /// About-sheet QA download statement.
  ///
  /// In en, this message translates to:
  /// **'Model downloads are a deterministic simulation of the pinned catalog; no network access exists.'**
  String get modelDownloadsSimulated;

  /// About-sheet production download statement.
  ///
  /// In en, this message translates to:
  /// **'Model downloads fetch the pinned artifacts from Hugging Face over HTTPS.'**
  String get modelDownloadsReal;

  /// About-sheet QA inference statement.
  ///
  /// In en, this message translates to:
  /// **'Inference is a deterministic UI simulation — no model weights, engine, or hardware measurement is included.'**
  String get inferenceSimulated;

  /// About-sheet production inference statement.
  ///
  /// In en, this message translates to:
  /// **'Inference runs the local engine on this device with the active model.'**
  String get inferenceLocal;

  /// About-sheet network and privacy statement.
  ///
  /// In en, this message translates to:
  /// **'Nothing else touches the network, and Golem reads no other app’s data.'**
  String get networkPrivacyStatement;

  /// Generic preference save failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save. Try again.'**
  String get saveFailed;

  /// First-run welcome headline.
  ///
  /// In en, this message translates to:
  /// **'A chat app that never phones home.'**
  String get firstRunTagline;

  /// First-run welcome introduction.
  ///
  /// In en, this message translates to:
  /// **'Golem loads one open model onto your phone and runs it there. No account, no server, and no copy of your conversations anywhere else.'**
  String get firstRunIntroduction;

  /// First-run privacy promise title.
  ///
  /// In en, this message translates to:
  /// **'Nothing leaves the device'**
  String get promisePrivateTitle;

  /// First-run privacy promise detail.
  ///
  /// In en, this message translates to:
  /// **'Messages live in Golem’s private storage.'**
  String get promisePrivateDetail;

  /// First-run offline promise title.
  ///
  /// In en, this message translates to:
  /// **'Works with no connection'**
  String get promiseOfflineTitle;

  /// First-run offline promise detail.
  ///
  /// In en, this message translates to:
  /// **'Once a model is downloaded, that’s it.'**
  String get promiseOfflineDetail;

  /// First-run advanced-controls promise title.
  ///
  /// In en, this message translates to:
  /// **'Every knob, if you want it'**
  String get promiseControlTitle;

  /// First-run advanced-controls promise detail.
  ///
  /// In en, this message translates to:
  /// **'Response style, system prompt, and sampling controls.'**
  String get promiseControlDetail;

  /// First-run welcome action.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// First-run model selection headline.
  ///
  /// In en, this message translates to:
  /// **'One model. Nothing to set up.'**
  String get oneModelHeadline;

  /// No compatible catalog model message.
  ///
  /// In en, this message translates to:
  /// **'Golem could not find a compatible model in this build.'**
  String get noCompatibleModel;

  /// First-run selected model explanation.
  ///
  /// In en, this message translates to:
  /// **'Golem downloads {modelName} once, then never needs the network to answer a chat.'**
  String modelOfflineIntroduction(String modelName);

  /// Disabled download action.
  ///
  /// In en, this message translates to:
  /// **'Download unavailable'**
  String get downloadUnavailable;

  /// Open alternate-model catalog action.
  ///
  /// In en, this message translates to:
  /// **'Choose a different model'**
  String get chooseDifferentModel;

  /// Context length in thousands of tokens.
  ///
  /// In en, this message translates to:
  /// **'{count}K tokens'**
  String tokensThousands(int count);

  /// Featured model explanation.
  ///
  /// In en, this message translates to:
  /// **'Good for everyday writing, summaries, and light code. Model speed depends on this phone and is not estimated before it runs.'**
  String get featuredModelDetail;

  /// First-run model catalog title.
  ///
  /// In en, this message translates to:
  /// **'All models'**
  String get allModelsTitle;

  /// QA catalog explanation.
  ///
  /// In en, this message translates to:
  /// **'This QA build shows the full pinned catalog. Downloads and model runs are simulated.'**
  String get catalogSimulationDetail;

  /// Production catalog explanation.
  ///
  /// In en, this message translates to:
  /// **'Models for this build’s engine can be selected. Larger models need the preferred device tier.'**
  String get catalogDeviceDetail;

  /// Model-selection prompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a model'**
  String get chooseModel;

  /// Complete first run action.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get startChatting;

  /// Pause model download action.
  ///
  /// In en, this message translates to:
  /// **'Pause download'**
  String get pauseDownload;

  /// Retry model download action.
  ///
  /// In en, this message translates to:
  /// **'Retry download'**
  String get retryDownload;

  /// Resume model download action.
  ///
  /// In en, this message translates to:
  /// **'Resume download'**
  String get resumeDownload;

  /// Installed model heading.
  ///
  /// In en, this message translates to:
  /// **'{modelName} is ready'**
  String modelReady(String modelName);

  /// Model verification heading.
  ///
  /// In en, this message translates to:
  /// **'Verifying {modelName}'**
  String modelVerifying(String modelName);

  /// Paused download heading.
  ///
  /// In en, this message translates to:
  /// **'Download paused'**
  String get downloadPaused;

  /// Failed download heading.
  ///
  /// In en, this message translates to:
  /// **'Download needs attention'**
  String get downloadNeedsAttention;

  /// Model download heading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {modelName}'**
  String modelDownloading(String modelName);

  /// Missing selected catalog entry.
  ///
  /// In en, this message translates to:
  /// **'The selected catalog entry is unavailable.'**
  String get selectedCatalogUnavailable;

  /// Generic model download failure.
  ///
  /// In en, this message translates to:
  /// **'The download failed. You can try again.'**
  String get downloadFailed;

  /// Model download storage failure with actionable byte amounts.
  ///
  /// In en, this message translates to:
  /// **'The model needs {required} free, but only {available} is available.'**
  String downloadInsufficientStorage(String required, String available);

  /// Model file hash verification failure.
  ///
  /// In en, this message translates to:
  /// **'{fileName} failed integrity verification. Retry the download.'**
  String downloadHashVerificationFailed(String fileName);

  /// Model file size verification failure.
  ///
  /// In en, this message translates to:
  /// **'{fileName} arrived at the wrong size. Retry the download.'**
  String downloadUnexpectedFileSize(String fileName);

  /// QA model install completion.
  ///
  /// In en, this message translates to:
  /// **'The deterministic QA simulation is complete; no weights were stored.'**
  String get downloadSimulationComplete;

  /// Production model install completion.
  ///
  /// In en, this message translates to:
  /// **'Verified on this device. Golem can now answer without a network connection.'**
  String get downloadComplete;

  /// Downloaded and total bytes.
  ///
  /// In en, this message translates to:
  /// **'{downloaded} of {total}'**
  String downloadAmount(String downloaded, String total);

  /// QA download progress detail.
  ///
  /// In en, this message translates to:
  /// **'{amount} · simulated. No network request or model-weight write occurs.'**
  String downloadSimulationProgress(String amount);

  /// Production download progress detail.
  ///
  /// In en, this message translates to:
  /// **'{amount}. Keep Golem open when practical; the platform may continue the transfer in the background.'**
  String downloadRealProgress(String amount);

  /// Unsupported-device onboarding headline.
  ///
  /// In en, this message translates to:
  /// **'Chats stay available.'**
  String get chatsStayAvailable;

  /// Generic unsupported-device message.
  ///
  /// In en, this message translates to:
  /// **'Golem cannot run models on this device.'**
  String get modelsUnavailableGeneric;

  /// Available features on unsupported devices.
  ///
  /// In en, this message translates to:
  /// **'No model will be downloaded. You can still open chats, history, settings, and exports.'**
  String get unsupportedFeaturesRemain;

  /// Skip models and complete first run.
  ///
  /// In en, this message translates to:
  /// **'Continue to Golem'**
  String get continueToGolem;

  /// First-run model preference save failure.
  ///
  /// In en, this message translates to:
  /// **'Your model choice could not be saved. Try again.'**
  String get modelChoiceSaveFailed;

  /// First-run completion save failure.
  ///
  /// In en, this message translates to:
  /// **'Golem could not save setup. Try again.'**
  String get setupSaveFailed;

  /// QA model download consent title.
  ///
  /// In en, this message translates to:
  /// **'Simulate this download?'**
  String get simulateDownloadTitle;

  /// Model download consent title.
  ///
  /// In en, this message translates to:
  /// **'Download this model?'**
  String get downloadModelTitle;

  /// QA model download consent body.
  ///
  /// In en, this message translates to:
  /// **'{modelName} is shown as a {size} download. This QA simulation uses no network and stores no model weights.'**
  String simulateDownloadMessage(String modelName, String size);

  /// Production model download consent body.
  ///
  /// In en, this message translates to:
  /// **'{modelName} downloads {size} from Hugging Face. Keep that space plus 500 MiB free. Wi-Fi is recommended; cellular data charges may apply.'**
  String downloadModelMessage(String modelName, String size);

  /// Decline an optional action.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// Start a QA simulation.
  ///
  /// In en, this message translates to:
  /// **'Simulate'**
  String get simulate;

  /// Deferred model setup heading.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up {modelName}'**
  String finishModelSetup(String modelName);

  /// Paused named-model heading.
  ///
  /// In en, this message translates to:
  /// **'{modelName} download paused'**
  String modelDownloadPaused(String modelName);

  /// Failed named-model heading.
  ///
  /// In en, this message translates to:
  /// **'{modelName} needs attention'**
  String modelNeedsAttention(String modelName);

  /// Deferred model setup prompt.
  ///
  /// In en, this message translates to:
  /// **'Download the selected model before sending. You can still draft messages and use the rest of Golem.'**
  String get setupDownloadPrompt;

  /// Short QA download explanation.
  ///
  /// In en, this message translates to:
  /// **'Deterministic QA simulation; no network or weights.'**
  String get qaDownloadShort;

  /// Download gating explanation.
  ///
  /// In en, this message translates to:
  /// **'The model must finish and verify before messages can be sent.'**
  String get downloadBeforeSending;

  /// Paused download explanation.
  ///
  /// In en, this message translates to:
  /// **'Resume when you are ready. Existing progress is kept.'**
  String get resumeProgressKept;

  /// Verification explanation.
  ///
  /// In en, this message translates to:
  /// **'Checking the downloaded files before they can run.'**
  String get checkingDownloadedFiles;

  /// Download failure explanation.
  ///
  /// In en, this message translates to:
  /// **'The download failed. Your chats are unaffected.'**
  String get downloadFailedChatsSafe;

  /// Ready state detail.
  ///
  /// In en, this message translates to:
  /// **'Ready.'**
  String get ready;

  /// Empty drawer history message.
  ///
  /// In en, this message translates to:
  /// **'Your conversations will appear here.'**
  String get conversationsAppearHere;

  /// Pinned conversation section and toast.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// Unpin conversation toast.
  ///
  /// In en, this message translates to:
  /// **'Unpinned'**
  String get unpinned;

  /// Earlier conversation section.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get earlier;

  /// Conversation overflow menu accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Conversation actions'**
  String get conversationActions;

  /// Delete named conversation confirmation.
  ///
  /// In en, this message translates to:
  /// **'“{title}” and all of its messages will be removed from this device.'**
  String deleteNamedChatMessage(String title);

  /// Delete conversation success toast.
  ///
  /// In en, this message translates to:
  /// **'Chat deleted'**
  String get chatDeleted;

  /// Used and total storage.
  ///
  /// In en, this message translates to:
  /// **'{used} of {total}'**
  String storageAmount(String used, String total);

  /// Dismiss conversation drawer accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Close conversations'**
  String get closeConversations;

  /// Discard failed generated response.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// Download missing active model action.
  ///
  /// In en, this message translates to:
  /// **'Download {modelName} ({size})'**
  String downloadNamedModel(String modelName, String size);

  /// Attachment sheet title and action.
  ///
  /// In en, this message translates to:
  /// **'Add to this chat'**
  String get addToChat;

  /// Photo library attachment source.
  ///
  /// In en, this message translates to:
  /// **'Photo library'**
  String get photoLibrary;

  /// Camera attachment source.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get takePhoto;

  /// Files attachment source.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// Image-capable attachment explanation.
  ///
  /// In en, this message translates to:
  /// **'Images are read on this device. {modelName} can see them; nothing is uploaded.'**
  String imagesPrivateDetail(String modelName);

  /// Text-only model attachment explanation.
  ///
  /// In en, this message translates to:
  /// **'{modelName} handles text only. Switch to a model that reads images to attach one.'**
  String imagesUnsupportedDetail(String modelName);

  /// Unsupported attachment type error.
  ///
  /// In en, this message translates to:
  /// **'That file type is not supported. Use a JPEG, PNG, or WebP image.'**
  String get unsupportedImageType;

  /// Oversized attachment error.
  ///
  /// In en, this message translates to:
  /// **'That image is too large to attach.'**
  String get imageTooLarge;

  /// Unreadable image error.
  ///
  /// In en, this message translates to:
  /// **'That image could not be read.'**
  String get imageUnreadable;

  /// Camera/photo permission error.
  ///
  /// In en, this message translates to:
  /// **'Golem needs access to your camera and photos. Turn it on in Settings to attach a picture.'**
  String get imagePermissionDenied;

  /// Generic attachment error.
  ///
  /// In en, this message translates to:
  /// **'That picture could not be added.'**
  String get imageAddFailed;

  /// Remove pending image accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Remove attached image'**
  String get removeAttachedImage;

  /// Conversation model picker title and accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Model for this chat'**
  String get modelForChat;

  /// Enabled reasoning control accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Reasoning on'**
  String get reasoningOn;

  /// Disabled reasoning control accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Reasoning off'**
  String get reasoningOff;

  /// Compact reasoning control label.
  ///
  /// In en, this message translates to:
  /// **'Think'**
  String get think;

  /// Empty chat accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Start a private conversation'**
  String get startPrivateConversation;

  /// Empty chat headline.
  ///
  /// In en, this message translates to:
  /// **'What are we building?'**
  String get whatAreWeBuilding;

  /// Unsupported-device empty chat headline.
  ///
  /// In en, this message translates to:
  /// **'Golem can’t run models here'**
  String get cannotRunModelsHere;

  /// QA empty-chat privacy statement.
  ///
  /// In en, this message translates to:
  /// **'This preview simulates {modelName} on this phone. Nothing you type here goes anywhere.'**
  String simulatedModelPrivacy(String modelName);

  /// Production empty-chat privacy statement.
  ///
  /// In en, this message translates to:
  /// **'{modelName} is loaded and running on this phone. Nothing you type here goes anywhere.'**
  String localModelPrivacy(String modelName);

  /// Starter prompt chip.
  ///
  /// In en, this message translates to:
  /// **'Draft a reply'**
  String get starterDraftReply;

  /// Starter prompt inserted into composer.
  ///
  /// In en, this message translates to:
  /// **'Draft a reply to this message: '**
  String get starterDraftReplyPrompt;

  /// Starter prompt chip.
  ///
  /// In en, this message translates to:
  /// **'Explain something'**
  String get starterExplain;

  /// Starter prompt inserted into composer.
  ///
  /// In en, this message translates to:
  /// **'Explain, simply: '**
  String get starterExplainPrompt;

  /// Starter prompt chip.
  ///
  /// In en, this message translates to:
  /// **'Rewrite my text'**
  String get starterRewrite;

  /// Starter prompt inserted into composer.
  ///
  /// In en, this message translates to:
  /// **'Rewrite this so it reads clearly: '**
  String get starterRewritePrompt;

  /// Starter prompt chip.
  ///
  /// In en, this message translates to:
  /// **'Summarise a note'**
  String get starterSummarise;

  /// Starter prompt inserted into composer.
  ///
  /// In en, this message translates to:
  /// **'Summarise this note: '**
  String get starterSummarisePrompt;

  /// Empty chat-search result.
  ///
  /// In en, this message translates to:
  /// **'No chats match your search.'**
  String get noChatsMatchSearch;

  /// Chat-search result count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 CHAT} other{{count} CHATS}}'**
  String searchResultCount(int count);

  /// Chat-search privacy footnote.
  ///
  /// In en, this message translates to:
  /// **'Search runs against the local database. No index is uploaded.'**
  String get localSearchPrivacy;

  /// Search result date and match count.
  ///
  /// In en, this message translates to:
  /// **'{date} · {count, plural, =1{1 match} other{{count} matches}}'**
  String searchMatchSummary(String date, int count);

  /// Partial generation token count.
  ///
  /// In en, this message translates to:
  /// **'Stopped after {count, plural, =1{1 token} other{{count} tokens}}'**
  String stoppedAfterTokens(int count);

  /// Copy message accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get copyMessage;

  /// Regenerate response accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Regenerate response'**
  String get regenerateResponse;

  /// Share message accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Share message'**
  String get shareMessage;

  /// Message overflow accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get messageActions;

  /// Regenerate model response action.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// Branch conversation action.
  ///
  /// In en, this message translates to:
  /// **'Branch from here'**
  String get branchFromHere;

  /// Generic share action.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Delete message action.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// Clipboard success toast.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// Conversation branch success toast.
  ///
  /// In en, this message translates to:
  /// **'New branch started'**
  String get newBranchStarted;

  /// User message action-sheet title.
  ///
  /// In en, this message translates to:
  /// **'Your message'**
  String get yourMessage;

  /// Assistant message action-sheet title.
  ///
  /// In en, this message translates to:
  /// **'Golem response'**
  String get golemResponse;

  /// Edit user message and regenerate action.
  ///
  /// In en, this message translates to:
  /// **'Edit and retry'**
  String get editAndRetry;

  /// Edit message dialog title.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessage;

  /// User speaker accessibility label.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get userSpeaker;

  /// Assistant speaker accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Golem'**
  String get assistantSpeaker;

  /// Save edited prompt and regenerate.
  ///
  /// In en, this message translates to:
  /// **'Save and regenerate'**
  String get saveAndRegenerate;

  /// Generic inference failure.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while generating a response.'**
  String get generationFailed;

  /// Recovery message for a missing persisted attachment.
  ///
  /// In en, this message translates to:
  /// **'An image in this conversation is no longer available. Delete this message and send it again.'**
  String get attachmentUnavailableFailure;

  /// Recovery message for a persisted model absent from the current catalog.
  ///
  /// In en, this message translates to:
  /// **'This chat’s model is not available in this version of Golem. Choose another model to continue.'**
  String get modelUnavailableFailure;

  /// Recovery message for an unsupported model profile or artifact shape.
  ///
  /// In en, this message translates to:
  /// **'Golem cannot use this model’s chat template or files. Choose a supported model to continue.'**
  String get unsupportedModelFailure;

  /// Recovery message when the active model cannot accept images.
  ///
  /// In en, this message translates to:
  /// **'This model cannot read the image in this message. Delete the message or choose a model that reads images.'**
  String get unsupportedImagesFailure;

  /// Recovery message for invalid installed model files.
  ///
  /// In en, this message translates to:
  /// **'The installed model is missing, damaged, or incompatible with this version of Golem. Choose another model or download it again.'**
  String get invalidModelArtifactFailure;

  /// Attachment persistence failure.
  ///
  /// In en, this message translates to:
  /// **'That image could not be saved. Try attaching it again.'**
  String get attachmentSaveFailed;

  /// Missing conversation model failure.
  ///
  /// In en, this message translates to:
  /// **'{modelName} is not downloaded on this device yet. Download it to use it in this chat.'**
  String modelMissingForChat(String modelName);

  /// Conversation context exhaustion failure.
  ///
  /// In en, this message translates to:
  /// **'This conversation is too long for the model’s context window. Start a new chat to continue.'**
  String get contextExhausted;

  /// Runtime out-of-memory failure.
  ///
  /// In en, this message translates to:
  /// **'The model ran out of memory while generating. Close other apps and try again.'**
  String get outOfMemory;

  /// Model load memory preflight failure.
  ///
  /// In en, this message translates to:
  /// **'There is not enough free memory to load this model. Close other apps or choose a smaller model.'**
  String get insufficientMemory;

  /// Reasoning exhausted output budget failure.
  ///
  /// In en, this message translates to:
  /// **'The model used its token budget before producing an answer. Try again or adjust the response settings.'**
  String get budgetExhausted;

  /// Images attached to a message for accessibility.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{} =1{ 1 image.} other{ {count} images.}}'**
  String imageCountSentence(int count);

  /// Inference rate and token count.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s · {count, plural, =1{1 token} other{{count} tokens}}'**
  String tokenRateSummary(String rate, int count);

  /// AI accuracy disclaimer.
  ///
  /// In en, this message translates to:
  /// **'AI responses can be inaccurate. Check important information.'**
  String get aiDisclaimer;

  /// Privacy screen summary.
  ///
  /// In en, this message translates to:
  /// **'Golem holds no account, sends no analytics, and drops its network permission once a model is downloaded. There is nothing to opt out of.'**
  String get privacyStatement;

  /// Local data settings section.
  ///
  /// In en, this message translates to:
  /// **'On this phone'**
  String get onThisPhone;

  /// Chat history persistence toggle.
  ///
  /// In en, this message translates to:
  /// **'Save chat history'**
  String get saveChatHistory;

  /// Disabled history persistence explanation.
  ///
  /// In en, this message translates to:
  /// **'Off means every chat disappears when you close it.'**
  String get saveHistoryOffDetail;

  /// User data actions section.
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get yourData;

  /// Export all chats action.
  ///
  /// In en, this message translates to:
  /// **'Export all chats'**
  String get exportAllChats;

  /// Delete all chats action.
  ///
  /// In en, this message translates to:
  /// **'Delete all chats'**
  String get deleteAllChats;

  /// Disable history confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Stop saving chats?'**
  String get stopSavingChatsTitle;

  /// Disable history confirmation body.
  ///
  /// In en, this message translates to:
  /// **'Chats already saved on this device are deleted now. Open chats stay until you close the app, and nothing new is written to disk.'**
  String get stopSavingChatsMessage;

  /// Keep history persistence action.
  ///
  /// In en, this message translates to:
  /// **'Keep saving'**
  String get keepSaving;

  /// Disable history and delete action.
  ///
  /// In en, this message translates to:
  /// **'Stop and delete'**
  String get stopAndDelete;

  /// Disable-history delete failure.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the saved chats. Try again.'**
  String get deleteSavedChatsFailed;

  /// System share subject for all-chat export.
  ///
  /// In en, this message translates to:
  /// **'Golem chats export'**
  String get chatsExportSubject;

  /// Delete all chats confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete all chats?'**
  String get deleteAllChatsTitle;

  /// Delete all chats confirmation body.
  ///
  /// In en, this message translates to:
  /// **'Every conversation is removed from this device. Downloaded models are kept.'**
  String get deleteAllChatsMessage;

  /// Delete all chats success toast.
  ///
  /// In en, this message translates to:
  /// **'Chats deleted'**
  String get chatsDeleted;

  /// Delete all chats failure toast.
  ///
  /// In en, this message translates to:
  /// **'Could not delete chats. Try again.'**
  String get deleteChatsFailed;

  /// System prompt explanation.
  ///
  /// In en, this message translates to:
  /// **'Standing instructions for every new response, sent ahead of the conversation. Leave it empty to keep the model’s default behavior.'**
  String get systemPromptDetail;

  /// System prompt field placeholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Answer briefly, in plain language.'**
  String get systemPromptExample;

  /// Reset system prompt action.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// System prompt privacy footnote.
  ///
  /// In en, this message translates to:
  /// **'The prompt applies to both models and stays on this device.'**
  String get systemPromptLocalFootnote;

  /// Storage breakdown load failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t read storage.'**
  String get storageReadFailed;

  /// Downloaded models storage section.
  ///
  /// In en, this message translates to:
  /// **'Downloaded models'**
  String get downloadedModels;

  /// Clear inference cache action.
  ///
  /// In en, this message translates to:
  /// **'Clear inference cache'**
  String get clearInferenceCache;

  /// Model deletion storage footnote.
  ///
  /// In en, this message translates to:
  /// **'Deleting a model frees the space immediately. Your chats are kept.'**
  String get modelDeletionFootnote;

  /// Cache clear success toast.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get cacheCleared;

  /// Available storage amount.
  ///
  /// In en, this message translates to:
  /// **'{size} free'**
  String storageFree(String size);

  /// Model storage legend.
  ///
  /// In en, this message translates to:
  /// **'Models {size}'**
  String storageModelsAmount(String size);

  /// Chat storage legend.
  ///
  /// In en, this message translates to:
  /// **'Chats {size}'**
  String storageChatsAmount(String size);

  /// Image storage legend.
  ///
  /// In en, this message translates to:
  /// **'Images {size}'**
  String storageImagesAmount(String size);

  /// Cache storage legend.
  ///
  /// In en, this message translates to:
  /// **'Cache {size}'**
  String storageCacheAmount(String size);

  /// Empty downloaded-model storage list.
  ///
  /// In en, this message translates to:
  /// **'No downloaded models yet.'**
  String get noDownloadedModels;

  /// Active model status token.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get active;

  /// Partial model download status token.
  ///
  /// In en, this message translates to:
  /// **'partial'**
  String get partial;

  /// Delete model artifact confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Delete {modelName} · {format}?'**
  String deleteModelArtifactTitle(String modelName, String format);

  /// Delete model storage confirmation body.
  ///
  /// In en, this message translates to:
  /// **'Removes {size} from this device. The model can be downloaded again later.'**
  String deleteModelStorageMessage(String size);

  /// Megabyte value.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String megabytes(int value);

  /// Open-source licenses introduction.
  ///
  /// In en, this message translates to:
  /// **'Golem is built with open-source software. These notices are available offline and include Dart, native engine, and model licenses used by this build.'**
  String get licensesIntroduction;

  /// License entry count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 license entry} other{{count} license entries}}'**
  String licenseEntries(int count);

  /// License registry load failure.
  ///
  /// In en, this message translates to:
  /// **'Licenses could not be loaded.'**
  String get licensesLoadFailed;

  /// License load retry explanation.
  ///
  /// In en, this message translates to:
  /// **'The bundled files are still on this device. Try loading them again.'**
  String get licensesRetryDetail;

  /// Collapsed license accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Show license for {name}'**
  String showLicenseFor(String name);

  /// Expanded license accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Hide license for {name}'**
  String hideLicenseFor(String name);

  /// Model attribution introduction.
  ///
  /// In en, this message translates to:
  /// **'Golem does not include model weights. It downloads the exact artifacts listed here only after you approve a download.'**
  String get modelAttributionIntroduction;

  /// Official model card link.
  ///
  /// In en, this message translates to:
  /// **'Official model card'**
  String get officialModelCard;

  /// License link label.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get license;

  /// Custom repository attribution footnote.
  ///
  /// In en, this message translates to:
  /// **'Repositories added by hand are governed by their own upstream terms. Golem does not certify or redistribute them.'**
  String get customRepositoryTerms;

  /// Accessibility value when startup fails.
  ///
  /// In en, this message translates to:
  /// **'Starting failed'**
  String get startupFailed;

  /// Startup failure caption.
  ///
  /// In en, this message translates to:
  /// **'Golem could not finish starting'**
  String get startupCouldNotFinish;

  /// Accessibility value while preparing onboarding.
  ///
  /// In en, this message translates to:
  /// **'Preparing first-run setup'**
  String get preparingFirstRun;

  /// Caption while preparing onboarding.
  ///
  /// In en, this message translates to:
  /// **'Preparing setup'**
  String get preparingSetup;

  /// Accessibility value during ordinary startup.
  ///
  /// In en, this message translates to:
  /// **'Starting Golem on this device'**
  String get startingOnDevice;

  /// Ordinary startup caption.
  ///
  /// In en, this message translates to:
  /// **'Getting things ready'**
  String get gettingReady;

  /// Splash-screen product tagline.
  ///
  /// In en, this message translates to:
  /// **'Private, local, and ready when you are.'**
  String get splashTagline;

  /// Chat persistence failure banner.
  ///
  /// In en, this message translates to:
  /// **'Chat history isn’t saving. Your latest changes could be lost when you close the app.'**
  String get chatHistoryNotSaving;

  /// In-progress persistence action.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// Live reasoning accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Reasoning, live'**
  String get reasoningLive;

  /// Expanded disclosure accessibility value.
  ///
  /// In en, this message translates to:
  /// **'Expanded'**
  String get expanded;

  /// Collapsed disclosure accessibility value.
  ///
  /// In en, this message translates to:
  /// **'Collapsed'**
  String get collapsed;

  /// Visible live reasoning label.
  ///
  /// In en, this message translates to:
  /// **'Reasoning · LIVE'**
  String get reasoningLiveBadge;

  /// Live generation speed.
  ///
  /// In en, this message translates to:
  /// **'Generating · {rate} tok/s'**
  String generatingAtRate(String rate);

  /// Missing message attachment accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Image is no longer available'**
  String get imageUnavailable;

  /// Loading message attachment accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Loading image'**
  String get loadingImage;

  /// Screen-reader announcement when generation starts.
  ///
  /// In en, this message translates to:
  /// **'Golem is responding'**
  String get golemResponding;

  /// Screen-reader announcement when generation completes.
  ///
  /// In en, this message translates to:
  /// **'Response finished'**
  String get responseFinished;

  /// Chat history load failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load chat history.'**
  String get chatHistoryLoadFailed;

  /// Conversation drawer button accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Open conversations'**
  String get openConversations;

  /// Image attachment source label.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// Short stop-generation label.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// Short send-message label.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// Code block copy accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// Label for an untagged code block.
  ///
  /// In en, this message translates to:
  /// **'CODE'**
  String get code;

  /// Model label on unsupported hardware.
  ///
  /// In en, this message translates to:
  /// **'Unsupported device'**
  String get unsupportedDevice;

  /// Short simulated-runtime qualifier.
  ///
  /// In en, this message translates to:
  /// **'simulated'**
  String get simulated;

  /// Short local-runtime qualifier.
  ///
  /// In en, this message translates to:
  /// **'on device'**
  String get onDevice;

  /// Response style screen title.
  ///
  /// In en, this message translates to:
  /// **'Response style'**
  String get responseStyle;

  /// Response style introduction.
  ///
  /// In en, this message translates to:
  /// **'How much room {modelName} has to improvise. This only affects new responses.'**
  String responseStyleDescription(String modelName);

  /// Hint for revealing sampling controls.
  ///
  /// In en, this message translates to:
  /// **'Turn on Advanced mode in Settings to set temperature, top-p and token budgets by hand.'**
  String get advancedSamplingHint;

  /// Sampling settings section.
  ///
  /// In en, this message translates to:
  /// **'Sampling'**
  String get sampling;

  /// Precise response style detail.
  ///
  /// In en, this message translates to:
  /// **'Sticks to the facts. Best for code and summaries.'**
  String get stylePreciseDetail;

  /// Balanced response style detail.
  ///
  /// In en, this message translates to:
  /// **'The model\'\'s own defaults. Recommended.'**
  String get styleBalancedDetail;

  /// Creative response style detail.
  ///
  /// In en, this message translates to:
  /// **'Looser and more varied. Occasionally wrong.'**
  String get styleCreativeDetail;

  /// Selected option accessibility label.
  ///
  /// In en, this message translates to:
  /// **'{name} selected'**
  String selectedOption(String name);

  /// Missing sampling profile note.
  ///
  /// In en, this message translates to:
  /// **'This model has no tunable profile on this build.'**
  String get noTunableProfile;

  /// Settings load failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load settings.'**
  String get settingsLoadFailed;

  /// Temperature sampling control.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get samplingTemperature;

  /// Top-p sampling control.
  ///
  /// In en, this message translates to:
  /// **'Top-p'**
  String get samplingTopP;

  /// Top-k sampling control.
  ///
  /// In en, this message translates to:
  /// **'Top-k'**
  String get samplingTopK;

  /// Disabled numeric sampling value.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// Maximum output-token control.
  ///
  /// In en, this message translates to:
  /// **'Max tokens'**
  String get maxTokens;

  /// Context window control.
  ///
  /// In en, this message translates to:
  /// **'Context length'**
  String get contextLength;

  /// Sampling value source caption.
  ///
  /// In en, this message translates to:
  /// **'· {style}'**
  String styleSource(String style);

  /// Default sampling value source caption.
  ///
  /// In en, this message translates to:
  /// **'· default'**
  String get defaultSource;

  /// Sampling budget constraint note.
  ///
  /// In en, this message translates to:
  /// **'Token budgets always leave 512 context tokens free for the prompt.'**
  String get tokenBudgetFootnote;

  /// Pinned thinking sampling constraint note.
  ///
  /// In en, this message translates to:
  /// **'Token budgets always leave 512 context tokens free for the prompt. Thinking mode keeps this model\'\'s pinned sampling; budgets apply to both modes.'**
  String get pinnedTokenBudgetFootnote;

  /// Model state load failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load model state.'**
  String get modelsLoadFailed;

  /// Generic model runtime failure shown instead of internal diagnostics.
  ///
  /// In en, this message translates to:
  /// **'The model runtime stopped unexpectedly. Try loading it again.'**
  String get modelRuntimeFailed;

  /// Empty installed-model list.
  ///
  /// In en, this message translates to:
  /// **'Nothing is installed yet.'**
  String get nothingInstalled;

  /// Empty simulated installed-model list.
  ///
  /// In en, this message translates to:
  /// **'Nothing is installed yet. Downloads here are a deterministic simulation.'**
  String get nothingInstalledSimulated;

  /// Model runtime section.
  ///
  /// In en, this message translates to:
  /// **'Runtime'**
  String get runtime;

  /// Custom model repository section.
  ///
  /// In en, this message translates to:
  /// **'Custom repository'**
  String get customRepository;

  /// No value.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No active model in simulated inference.
  ///
  /// In en, this message translates to:
  /// **'None · simulated inference'**
  String get noneSimulatedInference;

  /// Unload real model runtime action.
  ///
  /// In en, this message translates to:
  /// **'Unload Runtime'**
  String get unloadRuntime;

  /// Load real model runtime action.
  ///
  /// In en, this message translates to:
  /// **'Load Runtime'**
  String get loadRuntime;

  /// Unload simulated runtime action.
  ///
  /// In en, this message translates to:
  /// **'Unload Simulated Runtime'**
  String get unloadSimulatedRuntime;

  /// Load simulated runtime action.
  ///
  /// In en, this message translates to:
  /// **'Load Simulated Runtime'**
  String get loadSimulatedRuntime;

  /// Custom model save failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the model. Try again.'**
  String get modelSaveFailed;

  /// Custom model added toast.
  ///
  /// In en, this message translates to:
  /// **'Model added'**
  String get modelAdded;

  /// Malformed custom repository identifier.
  ///
  /// In en, this message translates to:
  /// **'Enter a public repository as owner/name, for example unsloth/gemma-4-E2B-it-qat-GGUF.'**
  String get repositoryMalformedIdentifier;

  /// Missing or private custom repository refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository could not be read. Check the name, and note that private repositories are not supported.'**
  String get repositoryNotFoundOrPrivate;

  /// Gated custom repository refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository requires accepting its licence on Hugging Face. Gated repositories are not supported.'**
  String get repositoryGated;

  /// Disabled custom repository refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository has been disabled on Hugging Face.'**
  String get repositoryDisabled;

  /// Custom repository rate-limit refusal.
  ///
  /// In en, this message translates to:
  /// **'Hugging Face is rate limiting this device. Try again shortly.'**
  String get repositoryRateLimited;

  /// Custom repository network failure.
  ///
  /// In en, this message translates to:
  /// **'Could not reach Hugging Face. Check your connection and try again.'**
  String get repositoryNetwork;

  /// Malformed custom repository metadata refusal.
  ///
  /// In en, this message translates to:
  /// **'Hugging Face returned something unexpected for that repository. Try again shortly.'**
  String get repositoryMalformedMetadata;

  /// Unsafe custom repository path refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository contains a file path this app will not write.'**
  String get repositoryUnsafePath;

  /// Custom repository has no loadable weights.
  ///
  /// In en, this message translates to:
  /// **'No weights this engine can load were found in that repository.'**
  String get repositoryNoWeights;

  /// Sharded custom model refusal.
  ///
  /// In en, this message translates to:
  /// **'That model is split across multiple weight files, which is not supported yet. Choose a single-file version.'**
  String get repositoryShardedWeights;

  /// Unsafe custom model weight format refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository publishes its weights in a format this app will not load. Only safetensors and GGUF are supported.'**
  String get repositoryUnsafeWeightFormat;

  /// Custom repository missing required file refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository is missing files the engine needs to load it.'**
  String get repositoryMissingRequiredFile;

  /// Inconsistent custom repository metadata refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository’s file listing disagrees with itself, so it cannot be pinned safely.'**
  String get repositoryInconsistentMetadata;

  /// Unsupported custom model architecture refusal.
  ///
  /// In en, this message translates to:
  /// **'This version of Golem cannot run that model architecture.'**
  String get repositoryUnsupportedArchitecture;

  /// Oversized custom model metadata refusal.
  ///
  /// In en, this message translates to:
  /// **'That model’s metadata is larger than this app will read.'**
  String get repositoryHeaderTooLarge;

  /// Duplicate custom repository refusal.
  ///
  /// In en, this message translates to:
  /// **'That repository has already been added.'**
  String get repositoryDuplicateEntry;

  /// Custom repository revision field placeholder.
  ///
  /// In en, this message translates to:
  /// **'main — or a branch, tag, or commit'**
  String get repositoryRevisionPlaceholder;

  /// Unrecognized custom model template warning.
  ///
  /// In en, this message translates to:
  /// **'This will download and can be deleted, but Golem cannot prompt it: its chat template is not one this version recognizes.'**
  String get unknownTemplateWarning;

  /// Simulated custom repository resolution note.
  ///
  /// In en, this message translates to:
  /// **'This build simulates downloads, so the revision and size below are synthesized rather than read from Hugging Face.'**
  String get simulatedRepositoryDetail;

  /// Custom repository support and consent note.
  ///
  /// In en, this message translates to:
  /// **'Only public repositories are supported. Nothing downloads until you have seen what resolving found.'**
  String get publicRepositoryDetail;

  /// Custom repository resolution progress.
  ///
  /// In en, this message translates to:
  /// **'Reading the repository…'**
  String get readingRepository;

  /// Multiple model weight files prompt.
  ///
  /// In en, this message translates to:
  /// **'This repository holds several weight files. Choose the one to install:'**
  String get chooseWeightFile;

  /// Unrecognized prompt profile value.
  ///
  /// In en, this message translates to:
  /// **'Not recognized'**
  String get notRecognized;

  /// Additional model file count.
  ///
  /// In en, this message translates to:
  /// **'+ {count, plural, =1{1 more file} other{{count} more files}}'**
  String moreFiles(int count);

  /// Add custom model action.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get addModel;

  /// Resolve custom repository action.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get resolveRepository;

  /// Active model badge.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get activeBadge;

  /// Model download status accessibility label.
  ///
  /// In en, this message translates to:
  /// **'{modelName} {engine} status'**
  String modelStatusLabel(String modelName, String engine);

  /// Model download progress label.
  ///
  /// In en, this message translates to:
  /// **'Download{suffix}'**
  String downloadProgressLabel(String suffix);

  /// Model verification progress.
  ///
  /// In en, this message translates to:
  /// **'Verifying files{suffix}…'**
  String verifyingFilesStatus(String suffix);

  /// Open model repository accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Open {repository} on Hugging Face'**
  String openRepository(String repository);

  /// Model size and file count.
  ///
  /// In en, this message translates to:
  /// **'{size} · {count, plural, =1{1 file} other{{count} files}}'**
  String modelSizeAndFiles(String size, int count);

  /// Simulated generation-rate result.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s · simulated'**
  String measuredSimulated(String rate);

  /// Measured generation rate on phone.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s on this phone'**
  String measuredOnPhone(String rate);

  /// Measured model performance row.
  ///
  /// In en, this message translates to:
  /// **'Measured'**
  String get measured;

  /// Download model action with size.
  ///
  /// In en, this message translates to:
  /// **'Download · {size}'**
  String downloadSizeAction(String size);

  /// Cancel model download and discard files.
  ///
  /// In en, this message translates to:
  /// **'Cancel and Discard'**
  String get cancelAndDiscard;

  /// Delete downloaded model action.
  ///
  /// In en, this message translates to:
  /// **'Delete Download'**
  String get deleteDownload;

  /// Model is not downloaded status.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get notDownloaded;

  /// Model download byte progress.
  ///
  /// In en, this message translates to:
  /// **'Downloading {downloaded} of {total}{suffix}'**
  String downloadingAmountStatus(
    String downloaded,
    String total,
    String suffix,
  );

  /// Paused model download status.
  ///
  /// In en, this message translates to:
  /// **'Paused at {downloaded}{suffix}'**
  String pausedAtStatus(String downloaded, String suffix);

  /// Model verification status.
  ///
  /// In en, this message translates to:
  /// **'Verifying{suffix}'**
  String verifyingStatus(String suffix);

  /// Installed model status.
  ///
  /// In en, this message translates to:
  /// **'Installed and verified{suffix}'**
  String installedVerifiedStatus(String suffix);

  /// Runtime unloaded state.
  ///
  /// In en, this message translates to:
  /// **'Unloaded'**
  String get unloaded;

  /// Runtime loading state.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// Simulated runtime loading state.
  ///
  /// In en, this message translates to:
  /// **'Loading simulation…'**
  String get loadingSimulation;

  /// Simulated runtime ready state.
  ///
  /// In en, this message translates to:
  /// **'Ready · simulated'**
  String get readySimulated;

  /// Runtime stopped state.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// Benchmark screen title.
  ///
  /// In en, this message translates to:
  /// **'Benchmark'**
  String get benchmark;

  /// Benchmark protocol section.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// Prompt label.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// Benchmark run type label.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// Warmup benchmark run.
  ///
  /// In en, this message translates to:
  /// **'Warmup'**
  String get warmup;

  /// Maximum benchmark output row.
  ///
  /// In en, this message translates to:
  /// **'Maximum output'**
  String get maximumOutput;

  /// Benchmark random seed row.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get seed;

  /// Benchmark protocol explanation.
  ///
  /// In en, this message translates to:
  /// **'Uses the tracked production prompt fixture. Output and timing are deterministic simulations only.'**
  String get benchmarkProtocolDetail;

  /// Benchmark simulation status section.
  ///
  /// In en, this message translates to:
  /// **'Simulation status'**
  String get simulationStatus;

  /// Device thermal status row.
  ///
  /// In en, this message translates to:
  /// **'Thermal'**
  String get thermal;

  /// Value not measured by simulation.
  ///
  /// In en, this message translates to:
  /// **'Not measured'**
  String get notMeasured;

  /// Low Power Mode status row.
  ///
  /// In en, this message translates to:
  /// **'Low Power Mode'**
  String get lowPowerMode;

  /// Value not read by simulation.
  ///
  /// In en, this message translates to:
  /// **'Not read'**
  String get notRead;

  /// Benchmark hardware validation row.
  ///
  /// In en, this message translates to:
  /// **'Hardware validation'**
  String get hardwareValidation;

  /// Negative value.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// Stop simulated benchmark action.
  ///
  /// In en, this message translates to:
  /// **'Stop Simulated Benchmark'**
  String get stopSimulatedBenchmark;

  /// Run simulated benchmark action.
  ///
  /// In en, this message translates to:
  /// **'Run Simulated Benchmark'**
  String get runSimulatedBenchmark;

  /// Simulated benchmark progress.
  ///
  /// In en, this message translates to:
  /// **'Generating deterministic result…'**
  String get generatingDeterministicResult;

  /// Simulated benchmark result section.
  ///
  /// In en, this message translates to:
  /// **'Simulated result'**
  String get simulatedResult;

  /// Benchmark case picker title.
  ///
  /// In en, this message translates to:
  /// **'Benchmark prompt'**
  String get benchmarkPrompt;

  /// Short benchmark case.
  ///
  /// In en, this message translates to:
  /// **'Short explanation'**
  String get shortExplanation;

  /// Medium benchmark case.
  ///
  /// In en, this message translates to:
  /// **'Medium review'**
  String get mediumReview;

  /// Long benchmark case.
  ///
  /// In en, this message translates to:
  /// **'Long synthesis'**
  String get longSynthesis;

  /// Benchmark result warning badge.
  ///
  /// In en, this message translates to:
  /// **'SIMULATED · NOT HARDWARE VALIDATED'**
  String get simulatedNotValidated;

  /// Generated token count row.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get generated;

  /// Token count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 token} other{{count} tokens}}'**
  String tokenCount(int count);

  /// Decode speed row.
  ///
  /// In en, this message translates to:
  /// **'Decode'**
  String get decode;

  /// Token generation rate.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s'**
  String tokenRate(String rate);

  /// Peak memory row.
  ///
  /// In en, this message translates to:
  /// **'Peak memory'**
  String get peakMemory;

  /// Simulated benchmark stop reason.
  ///
  /// In en, this message translates to:
  /// **'Simulated end of turn'**
  String get simulatedEndOfTurn;

  /// Benchmark export share title.
  ///
  /// In en, this message translates to:
  /// **'Golem simulated benchmark'**
  String get benchmarkExportTitle;

  /// Benchmark export share text.
  ///
  /// In en, this message translates to:
  /// **'Simulated benchmark JSON — not hardware validated.'**
  String get benchmarkExportText;

  /// Benchmark export action.
  ///
  /// In en, this message translates to:
  /// **'Export Simulated JSON'**
  String get exportSimulatedJson;

  /// Benchmark simulation warning.
  ///
  /// In en, this message translates to:
  /// **'This screen simulates the workflow. It does not measure this device.'**
  String get benchmarkSimulationNotice;

  /// Unsupported CPU explanation.
  ///
  /// In en, this message translates to:
  /// **'This device’s processor is missing an instruction set the local engine needs, so it cannot run models here.'**
  String get deviceMissingInstructionSet;

  /// Unsupported device-memory explanation.
  ///
  /// In en, this message translates to:
  /// **'This device has less memory than the smallest model Golem ships needs to run, so downloads are turned off here. Your chats and settings are unaffected.'**
  String get deviceBelowMemoryFloor;

  /// Out-of-memory recovery with known context size.
  ///
  /// In en, this message translates to:
  /// **'Ran out of memory at {tokens} tokens. Lower the context length or pick a smaller model.'**
  String outOfMemoryAtContext(int tokens);

  /// Lowercase default value caption.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get defaultLowercase;

  /// Lowercase precise style source.
  ///
  /// In en, this message translates to:
  /// **'precise'**
  String get stylePreciseLowercase;

  /// Lowercase balanced style source.
  ///
  /// In en, this message translates to:
  /// **'balanced'**
  String get styleBalancedLowercase;

  /// Lowercase creative style source.
  ///
  /// In en, this message translates to:
  /// **'creative'**
  String get styleCreativeLowercase;

  /// Hidden incompatible model count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 other model is built for a different engine and is not listed.} other{{count} other models are built for a different engine and are not listed.}} This build runs {engine}.'**
  String hiddenEngineModels(int count, String engine);

  /// Model row unavailable on device.
  ///
  /// In en, this message translates to:
  /// **'Not available on this device.'**
  String get notAvailableOnDevice;

  /// Model fixed by build configuration.
  ///
  /// In en, this message translates to:
  /// **'Pinned by this build.'**
  String get pinnedByBuild;

  /// Admission failure for other engine.
  ///
  /// In en, this message translates to:
  /// **'This build uses the {engine} engine.'**
  String otherEngineAdmission(String engine);

  /// Lighter model admission with unknown memory.
  ///
  /// In en, this message translates to:
  /// **'Golem could not read this phone’s memory, so it ships the lighter model here.'**
  String get memoryUnreadableLighterModel;

  /// Larger model memory refusal.
  ///
  /// In en, this message translates to:
  /// **'Needs more memory than this phone reports.'**
  String get needsMoreReportedMemory;

  /// Model admission refused on this device.
  ///
  /// In en, this message translates to:
  /// **'Models are unavailable on this device.'**
  String get modelsUnavailableOnDevice;

  /// Unresolved custom repository refusal.
  ///
  /// In en, this message translates to:
  /// **'This repository has not been resolved against Hugging Face, so its files are unknown. Add it again to resolve it.'**
  String get unresolvedRepositoryReason;

  /// Installed model incompatible with build engine.
  ///
  /// In en, this message translates to:
  /// **'Installed, but this build runs {buildEngine} and cannot load {modelEngine} models.'**
  String installedOtherEngine(String buildEngine, String modelEngine);

  /// Installed model template unsupported.
  ///
  /// In en, this message translates to:
  /// **'Installed, but Golem does not recognize this model’s chat template, so it cannot prompt it.'**
  String get unrecognizedChatTemplate;

  /// Model selection blocked during download.
  ///
  /// In en, this message translates to:
  /// **'Pick it once the download finishes.'**
  String get pickAfterDownload;

  /// Model selection blocked on paused download.
  ///
  /// In en, this message translates to:
  /// **'Resume the download to use it in this chat.'**
  String get resumeForChat;

  /// Model selection blocked after failed download.
  ///
  /// In en, this message translates to:
  /// **'The download did not finish, so it cannot be picked yet.'**
  String get unfinishedDownload;

  /// Model selection requires download.
  ///
  /// In en, this message translates to:
  /// **'Download it to use it in this chat.'**
  String get downloadForChat;

  /// Hand-added model summary.
  ///
  /// In en, this message translates to:
  /// **'Added by you from Hugging Face.'**
  String get customModelSummary;

  /// Single model transfer slot note.
  ///
  /// In en, this message translates to:
  /// **'Another model is downloading.'**
  String get anotherModelDownloading;

  /// Model picker downloading label.
  ///
  /// In en, this message translates to:
  /// **'Downloading{suffix}'**
  String downloadingStatus(String suffix);

  /// Model picker verification label.
  ///
  /// In en, this message translates to:
  /// **'Verifying files{suffix}'**
  String verifyingFilesPicker(String suffix);

  /// Paused model download detail.
  ///
  /// In en, this message translates to:
  /// **'Paused at {downloaded} of {total}{suffix}.'**
  String pausedDownloadAmount(String downloaded, String total, String suffix);

  /// Image-capable model detail.
  ///
  /// In en, this message translates to:
  /// **'reads pictures'**
  String get readsPictures;

  /// Simulated model speed detail.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s simulated'**
  String modelSpeedSimulated(String rate);

  /// Measured model speed detail.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s on this phone'**
  String modelSpeedOnPhone(String rate);

  /// Default model recommendation reason.
  ///
  /// In en, this message translates to:
  /// **'This build’s default model.'**
  String get buildDefaultModel;

  /// Recommendation based on unknown memory.
  ///
  /// In en, this message translates to:
  /// **'The lighter model, picked because this phone’s memory could not be read.'**
  String get lighterModelUnknownMemory;

  /// Preferred-tier recommendation reason.
  ///
  /// In en, this message translates to:
  /// **'This phone has the memory for the larger model.'**
  String get largerModelFits;

  /// Light-tier recommendation reason.
  ///
  /// In en, this message translates to:
  /// **'Sized to fit this phone’s memory.'**
  String get sizedForPhone;

  /// Sideloaded model picker footnote.
  ///
  /// In en, this message translates to:
  /// **'This build runs {modelName} from a path it pins, so this chat cannot switch models.'**
  String sideloadPreventsSwitch(String modelName);

  /// Model picker behavior footnote.
  ///
  /// In en, this message translates to:
  /// **'The model you pick loads with your next message.'**
  String get modelLoadsNextMessage;

  /// Selected model accessibility label.
  ///
  /// In en, this message translates to:
  /// **'Selected model'**
  String get selectedModel;

  /// Open model management action.
  ///
  /// In en, this message translates to:
  /// **'Manage models'**
  String get manageModels;

  /// Gemma catalog summary.
  ///
  /// In en, this message translates to:
  /// **'A balanced all-rounder for everyday writing, summarising and light code.'**
  String get gemmaModelSummary;

  /// Qwen 2B catalog summary.
  ///
  /// In en, this message translates to:
  /// **'The smallest and quickest to answer. Best for short questions, and for phones with less memory to spare.'**
  String get qwenTwoBModelSummary;

  /// Qwen 4B catalog summary.
  ///
  /// In en, this message translates to:
  /// **'Leans towards code and maths, and can think a problem through before it answers.'**
  String get qwenFourBModelSummary;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'en',
    'es',
    'fr',
    'hi',
    'id',
    'ja',
    'ko',
    'pl',
    'pt',
    'tr',
    'vi',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'tr':
      return AppLocalizationsTr();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
