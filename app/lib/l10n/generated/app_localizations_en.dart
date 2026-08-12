// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Golem';

  @override
  String get startingUp => 'Starting up';

  @override
  String get launchTakingLonger => 'Starting is taking longer than expected.';

  @override
  String get launchStorageUnavailable =>
      'Golem could not access its storage on this device.';

  @override
  String get launchInvalidConfiguration =>
      'This build of Golem is misconfigured and cannot start.';

  @override
  String get launchUnknownFailure => 'Golem could not finish starting.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get back => 'Back';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get download => 'Download';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get retry => 'Retry';

  @override
  String get reset => 'Reset';

  @override
  String get done => 'Done';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get chatTitle => 'Chat';

  @override
  String get settingsSectionModel => 'MODEL';

  @override
  String get settingsSectionApp => 'APP';

  @override
  String get settingsSectionAbout => 'ABOUT';

  @override
  String get settingsModel => 'Model';

  @override
  String get settingsResponseStyle => 'Response style';

  @override
  String get settingsSystemPrompt => 'System prompt';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsPrivacyData => 'Privacy & data';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsBenchmark => 'Benchmark';

  @override
  String get settingsModelAttribution => 'Model attribution';

  @override
  String get settingsOpenSourceLicenses => 'Open-source licenses';

  @override
  String get settingsAboutGolem => 'About Golem';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePolish => 'Polski';

  @override
  String get languageSystemDetail =>
      'Use the language selected for this device.';

  @override
  String get languageSaveFailed =>
      'The language could not be saved. Your previous choice was restored.';

  @override
  String get preferencesLoadFailed => 'Could not load preferences.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get showInferenceMetrics => 'Show inference metrics';

  @override
  String get alwaysExpandReasoning => 'Always expand reasoning';

  @override
  String get hapticsOnSend => 'Haptics on send';

  @override
  String get textSize => 'Text size';

  @override
  String get newChat => 'New chat';

  @override
  String get searchChats => 'Search chats';

  @override
  String get settings => 'Settings';

  @override
  String get rename => 'Rename';

  @override
  String get renameChat => 'Rename chat';

  @override
  String get shareTranscript => 'Share transcript';

  @override
  String get pinToTop => 'Pin to top';

  @override
  String get unpin => 'Unpin';

  @override
  String get deleteChatTitle => 'Delete chat?';

  @override
  String get deleteChatMessage => 'This chat will be removed from this device.';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get previousSevenDays => 'Previous 7 days';

  @override
  String get older => 'Older';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get noSearchResults => 'No chats found';

  @override
  String get jumpToLatest => 'Jump to latest message';

  @override
  String get messagePlaceholder => 'Message Golem';

  @override
  String get sendMessage => 'Send message';

  @override
  String get stopGenerating => 'Stop generating';

  @override
  String get attach => 'Attach';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get reasoning => 'Reasoning';

  @override
  String get showReasoning => 'Show reasoning';

  @override
  String get hideReasoning => 'Hide reasoning';

  @override
  String get thinking => 'Thinking…';

  @override
  String get model => 'Model';

  @override
  String get models => 'Models';

  @override
  String get allModels => 'All';

  @override
  String get installedModels => 'Installed';

  @override
  String get recommended => 'RECOMMENDED';

  @override
  String get activeModel => 'Active model';

  @override
  String get state => 'State';

  @override
  String get revision => 'Revision';

  @override
  String get quantization => 'Quantization';

  @override
  String get size => 'Size';

  @override
  String get promptProfile => 'Prompt profile';

  @override
  String get repository => 'Repository';

  @override
  String get context => 'Context';

  @override
  String get input => 'Input';

  @override
  String get textOnly => 'Text';

  @override
  String get textAndImages => 'Text + images';

  @override
  String get downloadProgress => 'Download progress';

  @override
  String get verifyingFiles => 'Verifying files…';

  @override
  String get keep => 'Keep';

  @override
  String deleteModelTitle(String modelName) {
    return 'Delete $modelName?';
  }

  @override
  String get deleteModelMessage =>
      'The downloaded files will be removed from this device. You can download them again later.';

  @override
  String downloadSize(String size) {
    return 'Download · $size';
  }

  @override
  String bytesDecimal(String value) {
    return '$value GB';
  }

  @override
  String chatCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chats',
      one: '1 chat',
      zero: 'No chats',
    );
    return '$_temp0';
  }

  @override
  String get defaultValue => 'Default';

  @override
  String get customValue => 'Custom';

  @override
  String get stylePrecise => 'Precise';

  @override
  String get styleBalanced => 'Balanced';

  @override
  String get styleCreative => 'Creative';

  @override
  String get advancedMode => 'Advanced mode';

  @override
  String get advancedModeDetail =>
      'Sampling controls, a custom system prompt, and loading any Hugging Face repository by hand.';

  @override
  String get aboutLegal => 'About & legal';

  @override
  String get openSourcePrivacyFootnote =>
      'Golem is open source. Nothing on this screen sends anything anywhere.';

  @override
  String get simulatedInferenceBanner =>
      'SIMULATED INFERENCE · No hardware validation';

  @override
  String get theme => 'Theme';

  @override
  String get inTranscript => 'In the transcript';

  @override
  String get textPreview => 'Looks about right.';

  @override
  String percentValue(int value) {
    return '$value percent';
  }

  @override
  String languageSelected(String language) {
    return '$language selected';
  }

  @override
  String get modelDownloadsSimulated =>
      'Model downloads are a deterministic simulation of the pinned catalog; no network access exists.';

  @override
  String get modelDownloadsReal =>
      'Model downloads fetch the pinned artifacts from Hugging Face over HTTPS.';

  @override
  String get inferenceSimulated =>
      'Inference is a deterministic UI simulation — no model weights, engine, or hardware measurement is included.';

  @override
  String get inferenceLocal =>
      'Inference runs the local engine on this device with the active model.';

  @override
  String get networkPrivacyStatement =>
      'Nothing else touches the network, and Golem reads no other app’s data.';

  @override
  String get saveFailed => 'Couldn\'t save. Try again.';

  @override
  String get firstRunTagline => 'A chat app that never phones home.';

  @override
  String get firstRunIntroduction =>
      'Golem loads one open model onto your phone and runs it there. No account, no server, and no copy of your conversations anywhere else.';

  @override
  String get promisePrivateTitle => 'Nothing leaves the device';

  @override
  String get promisePrivateDetail =>
      'Messages live in Golem’s private storage.';

  @override
  String get promiseOfflineTitle => 'Works with no connection';

  @override
  String get promiseOfflineDetail => 'Once a model is downloaded, that’s it.';

  @override
  String get promiseControlTitle => 'Every knob, if you want it';

  @override
  String get promiseControlDetail =>
      'Response style, system prompt, and sampling controls.';

  @override
  String get getStarted => 'Get started';

  @override
  String get oneModelHeadline => 'One model. Nothing to set up.';

  @override
  String get noCompatibleModel =>
      'Golem could not find a compatible model in this build.';

  @override
  String modelOfflineIntroduction(String modelName) {
    return 'Golem downloads $modelName once, then never needs the network to answer a chat.';
  }

  @override
  String get downloadUnavailable => 'Download unavailable';

  @override
  String get chooseDifferentModel => 'Choose a different model';

  @override
  String tokensThousands(int count) {
    return '${count}K tokens';
  }

  @override
  String get featuredModelDetail =>
      'Good for everyday writing, summaries, and light code. Model speed depends on this phone and is not estimated before it runs.';

  @override
  String get allModelsTitle => 'All models';

  @override
  String get catalogSimulationDetail =>
      'This QA build shows the full pinned catalog. Downloads and model runs are simulated.';

  @override
  String get catalogDeviceDetail =>
      'Models for this build’s engine can be selected. Larger models need the preferred device tier.';

  @override
  String get chooseModel => 'Choose a model';

  @override
  String get startChatting => 'Start chatting';

  @override
  String get pauseDownload => 'Pause download';

  @override
  String get retryDownload => 'Retry download';

  @override
  String get resumeDownload => 'Resume download';

  @override
  String modelReady(String modelName) {
    return '$modelName is ready';
  }

  @override
  String modelVerifying(String modelName) {
    return 'Verifying $modelName';
  }

  @override
  String get downloadPaused => 'Download paused';

  @override
  String get downloadNeedsAttention => 'Download needs attention';

  @override
  String modelDownloading(String modelName) {
    return 'Downloading $modelName';
  }

  @override
  String get selectedCatalogUnavailable =>
      'The selected catalog entry is unavailable.';

  @override
  String get downloadFailed => 'The download failed. You can try again.';

  @override
  String downloadInsufficientStorage(String required, String available) {
    return 'The model needs $required free, but only $available is available.';
  }

  @override
  String downloadHashVerificationFailed(String fileName) {
    return '$fileName failed integrity verification. Retry the download.';
  }

  @override
  String downloadUnexpectedFileSize(String fileName) {
    return '$fileName arrived at the wrong size. Retry the download.';
  }

  @override
  String get downloadSimulationComplete =>
      'The deterministic QA simulation is complete; no weights were stored.';

  @override
  String get downloadComplete =>
      'Verified on this device. Golem can now answer without a network connection.';

  @override
  String downloadAmount(String downloaded, String total) {
    return '$downloaded of $total';
  }

  @override
  String downloadSimulationProgress(String amount) {
    return '$amount · simulated. No network request or model-weight write occurs.';
  }

  @override
  String downloadRealProgress(String amount) {
    return '$amount. Keep Golem open when practical; the platform may continue the transfer in the background.';
  }

  @override
  String get chatsStayAvailable => 'Chats stay available.';

  @override
  String get modelsUnavailableGeneric =>
      'Golem cannot run models on this device.';

  @override
  String get unsupportedFeaturesRemain =>
      'No model will be downloaded. You can still open chats, history, settings, and exports.';

  @override
  String get continueToGolem => 'Continue to Golem';

  @override
  String get modelChoiceSaveFailed =>
      'Your model choice could not be saved. Try again.';

  @override
  String get setupSaveFailed => 'Golem could not save setup. Try again.';

  @override
  String get simulateDownloadTitle => 'Simulate this download?';

  @override
  String get downloadModelTitle => 'Download this model?';

  @override
  String simulateDownloadMessage(String modelName, String size) {
    return '$modelName is shown as a $size download. This QA simulation uses no network and stores no model weights.';
  }

  @override
  String downloadModelMessage(String modelName, String size) {
    return '$modelName downloads $size from Hugging Face. Keep that space plus 500 MiB free. Wi-Fi is recommended; cellular data charges may apply.';
  }

  @override
  String get notNow => 'Not now';

  @override
  String get simulate => 'Simulate';

  @override
  String finishModelSetup(String modelName) {
    return 'Finish setting up $modelName';
  }

  @override
  String modelDownloadPaused(String modelName) {
    return '$modelName download paused';
  }

  @override
  String modelNeedsAttention(String modelName) {
    return '$modelName needs attention';
  }

  @override
  String get setupDownloadPrompt =>
      'Download the selected model before sending. You can still draft messages and use the rest of Golem.';

  @override
  String get qaDownloadShort =>
      'Deterministic QA simulation; no network or weights.';

  @override
  String get downloadBeforeSending =>
      'The model must finish and verify before messages can be sent.';

  @override
  String get resumeProgressKept =>
      'Resume when you are ready. Existing progress is kept.';

  @override
  String get checkingDownloadedFiles =>
      'Checking the downloaded files before they can run.';

  @override
  String get downloadFailedChatsSafe =>
      'The download failed. Your chats are unaffected.';

  @override
  String get ready => 'Ready.';

  @override
  String get conversationsAppearHere => 'Your conversations will appear here.';

  @override
  String get pinned => 'Pinned';

  @override
  String get unpinned => 'Unpinned';

  @override
  String get earlier => 'Earlier';

  @override
  String get conversationActions => 'Conversation actions';

  @override
  String deleteNamedChatMessage(String title) {
    return '“$title” and all of its messages will be removed from this device.';
  }

  @override
  String get chatDeleted => 'Chat deleted';

  @override
  String storageAmount(String used, String total) {
    return '$used of $total';
  }

  @override
  String get closeConversations => 'Close conversations';

  @override
  String get discard => 'Discard';

  @override
  String downloadNamedModel(String modelName, String size) {
    return 'Download $modelName ($size)';
  }

  @override
  String get addToChat => 'Add to this chat';

  @override
  String get photoLibrary => 'Photo library';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get files => 'Files';

  @override
  String imagesPrivateDetail(String modelName) {
    return 'Images are read on this device. $modelName can see them; nothing is uploaded.';
  }

  @override
  String imagesUnsupportedDetail(String modelName) {
    return '$modelName handles text only. Switch to a model that reads images to attach one.';
  }

  @override
  String get unsupportedImageType =>
      'That file type is not supported. Use a JPEG, PNG, or WebP image.';

  @override
  String get imageTooLarge => 'That image is too large to attach.';

  @override
  String get imageUnreadable => 'That image could not be read.';

  @override
  String get imagePermissionDenied =>
      'Golem needs access to your camera and photos. Turn it on in Settings to attach a picture.';

  @override
  String get imageAddFailed => 'That picture could not be added.';

  @override
  String get removeAttachedImage => 'Remove attached image';

  @override
  String get modelForChat => 'Model for this chat';

  @override
  String get reasoningOn => 'Reasoning on';

  @override
  String get reasoningOff => 'Reasoning off';

  @override
  String get think => 'Think';

  @override
  String get startPrivateConversation => 'Start a private conversation';

  @override
  String get whatAreWeBuilding => 'What are we building?';

  @override
  String get cannotRunModelsHere => 'Golem can’t run models here';

  @override
  String simulatedModelPrivacy(String modelName) {
    return 'This preview simulates $modelName on this phone. Nothing you type here goes anywhere.';
  }

  @override
  String localModelPrivacy(String modelName) {
    return '$modelName is loaded and running on this phone. Nothing you type here goes anywhere.';
  }

  @override
  String get starterDraftReply => 'Draft a reply';

  @override
  String get starterDraftReplyPrompt => 'Draft a reply to this message: ';

  @override
  String get starterExplain => 'Explain something';

  @override
  String get starterExplainPrompt => 'Explain, simply: ';

  @override
  String get starterRewrite => 'Rewrite my text';

  @override
  String get starterRewritePrompt => 'Rewrite this so it reads clearly: ';

  @override
  String get starterSummarise => 'Summarise a note';

  @override
  String get starterSummarisePrompt => 'Summarise this note: ';

  @override
  String get noChatsMatchSearch => 'No chats match your search.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count CHATS',
      one: '1 CHAT',
    );
    return '$_temp0';
  }

  @override
  String get localSearchPrivacy =>
      'Search runs against the local database. No index is uploaded.';

  @override
  String searchMatchSummary(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$date · $_temp0';
  }

  @override
  String stoppedAfterTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '1 token',
    );
    return 'Stopped after $_temp0';
  }

  @override
  String get copyMessage => 'Copy message';

  @override
  String get regenerateResponse => 'Regenerate response';

  @override
  String get shareMessage => 'Share message';

  @override
  String get messageActions => 'Message actions';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get branchFromHere => 'Branch from here';

  @override
  String get share => 'Share';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get newBranchStarted => 'New branch started';

  @override
  String get yourMessage => 'Your message';

  @override
  String get golemResponse => 'Golem response';

  @override
  String get editAndRetry => 'Edit and retry';

  @override
  String get editMessage => 'Edit message';

  @override
  String get userSpeaker => 'You';

  @override
  String get assistantSpeaker => 'Golem';

  @override
  String get saveAndRegenerate => 'Save and regenerate';

  @override
  String get generationFailed =>
      'Something went wrong while generating a response.';

  @override
  String get attachmentUnavailableFailure =>
      'An image in this conversation is no longer available. Delete this message and send it again.';

  @override
  String get modelUnavailableFailure =>
      'This chat’s model is not available in this version of Golem. Choose another model to continue.';

  @override
  String get unsupportedModelFailure =>
      'Golem cannot use this model’s chat template or files. Choose a supported model to continue.';

  @override
  String get unsupportedImagesFailure =>
      'This model cannot read the image in this message. Delete the message or choose a model that reads images.';

  @override
  String get invalidModelArtifactFailure =>
      'The installed model is missing, damaged, or incompatible with this version of Golem. Choose another model or download it again.';

  @override
  String get attachmentSaveFailed =>
      'That image could not be saved. Try attaching it again.';

  @override
  String modelMissingForChat(String modelName) {
    return '$modelName is not downloaded on this device yet. Download it to use it in this chat.';
  }

  @override
  String get contextExhausted =>
      'This conversation is too long for the model’s context window. Start a new chat to continue.';

  @override
  String get outOfMemory =>
      'The model ran out of memory while generating. Close other apps and try again.';

  @override
  String get insufficientMemory =>
      'There is not enough free memory to load this model. Close other apps or choose a smaller model.';

  @override
  String get budgetExhausted =>
      'The model used its token budget before producing an answer. Try again or adjust the response settings.';

  @override
  String imageCountSentence(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' $count images.',
      one: ' 1 image.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String tokenRateSummary(String rate, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '1 token',
    );
    return '$rate tok/s · $_temp0';
  }

  @override
  String get aiDisclaimer =>
      'AI responses can be inaccurate. Check important information.';

  @override
  String get privacyStatement =>
      'Golem holds no account, sends no analytics, and drops its network permission once a model is downloaded. There is nothing to opt out of.';

  @override
  String get onThisPhone => 'On this phone';

  @override
  String get saveChatHistory => 'Save chat history';

  @override
  String get saveHistoryOffDetail =>
      'Off means every chat disappears when you close it.';

  @override
  String get yourData => 'Your data';

  @override
  String get exportAllChats => 'Export all chats';

  @override
  String get deleteAllChats => 'Delete all chats';

  @override
  String get stopSavingChatsTitle => 'Stop saving chats?';

  @override
  String get stopSavingChatsMessage =>
      'Chats already saved on this device are deleted now. Open chats stay until you close the app, and nothing new is written to disk.';

  @override
  String get keepSaving => 'Keep saving';

  @override
  String get stopAndDelete => 'Stop and delete';

  @override
  String get deleteSavedChatsFailed =>
      'Could not delete the saved chats. Try again.';

  @override
  String get chatsExportSubject => 'Golem chats export';

  @override
  String get deleteAllChatsTitle => 'Delete all chats?';

  @override
  String get deleteAllChatsMessage =>
      'Every conversation is removed from this device. Downloaded models are kept.';

  @override
  String get chatsDeleted => 'Chats deleted';

  @override
  String get deleteChatsFailed => 'Could not delete chats. Try again.';

  @override
  String get systemPromptDetail =>
      'Standing instructions for every new response, sent ahead of the conversation. Leave it empty to keep the model’s default behavior.';

  @override
  String get systemPromptExample => 'e.g. Answer briefly, in plain language.';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get systemPromptLocalFootnote =>
      'The prompt applies to both models and stays on this device.';

  @override
  String get storageReadFailed => 'Couldn\'t read storage.';

  @override
  String get downloadedModels => 'Downloaded models';

  @override
  String get clearInferenceCache => 'Clear inference cache';

  @override
  String get modelDeletionFootnote =>
      'Deleting a model frees the space immediately. Your chats are kept.';

  @override
  String get cacheCleared => 'Cache cleared';

  @override
  String storageFree(String size) {
    return '$size free';
  }

  @override
  String storageModelsAmount(String size) {
    return 'Models $size';
  }

  @override
  String storageChatsAmount(String size) {
    return 'Chats $size';
  }

  @override
  String storageImagesAmount(String size) {
    return 'Images $size';
  }

  @override
  String storageCacheAmount(String size) {
    return 'Cache $size';
  }

  @override
  String get noDownloadedModels => 'No downloaded models yet.';

  @override
  String get active => 'active';

  @override
  String get partial => 'partial';

  @override
  String deleteModelArtifactTitle(String modelName, String format) {
    return 'Delete $modelName · $format?';
  }

  @override
  String deleteModelStorageMessage(String size) {
    return 'Removes $size from this device. The model can be downloaded again later.';
  }

  @override
  String megabytes(int value) {
    return '$value MB';
  }

  @override
  String get licensesIntroduction =>
      'Golem is built with open-source software. These notices are available offline and include Dart, native engine, and model licenses used by this build.';

  @override
  String licenseEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count license entries',
      one: '1 license entry',
    );
    return '$_temp0';
  }

  @override
  String get licensesLoadFailed => 'Licenses could not be loaded.';

  @override
  String get licensesRetryDetail =>
      'The bundled files are still on this device. Try loading them again.';

  @override
  String showLicenseFor(String name) {
    return 'Show license for $name';
  }

  @override
  String hideLicenseFor(String name) {
    return 'Hide license for $name';
  }

  @override
  String get modelAttributionIntroduction =>
      'Golem does not include model weights. It downloads the exact artifacts listed here only after you approve a download.';

  @override
  String get officialModelCard => 'Official model card';

  @override
  String get license => 'License';

  @override
  String get customRepositoryTerms =>
      'Repositories added by hand are governed by their own upstream terms. Golem does not certify or redistribute them.';

  @override
  String get startupFailed => 'Starting failed';

  @override
  String get startupCouldNotFinish => 'Golem could not finish starting';

  @override
  String get preparingFirstRun => 'Preparing first-run setup';

  @override
  String get preparingSetup => 'Preparing setup';

  @override
  String get startingOnDevice => 'Starting Golem on this device';

  @override
  String get gettingReady => 'Getting things ready';

  @override
  String get splashTagline => 'Private, local, and ready when you are.';

  @override
  String get chatHistoryNotSaving =>
      'Chat history isn’t saving. Your latest changes could be lost when you close the app.';

  @override
  String get saving => 'Saving…';

  @override
  String get reasoningLive => 'Reasoning, live';

  @override
  String get expanded => 'Expanded';

  @override
  String get collapsed => 'Collapsed';

  @override
  String get reasoningLiveBadge => 'Reasoning · LIVE';

  @override
  String generatingAtRate(String rate) {
    return 'Generating · $rate tok/s';
  }

  @override
  String get imageUnavailable => 'Image is no longer available';

  @override
  String get loadingImage => 'Loading image';

  @override
  String get golemResponding => 'Golem is responding';

  @override
  String get responseFinished => 'Response finished';

  @override
  String get chatHistoryLoadFailed => 'Couldn\'t load chat history.';

  @override
  String get openConversations => 'Open conversations';

  @override
  String get images => 'Images';

  @override
  String get stop => 'Stop';

  @override
  String get send => 'Send';

  @override
  String get copyCode => 'Copy code';

  @override
  String get code => 'CODE';

  @override
  String get unsupportedDevice => 'Unsupported device';

  @override
  String get simulated => 'simulated';

  @override
  String get onDevice => 'on device';

  @override
  String get responseStyle => 'Response style';

  @override
  String responseStyleDescription(String modelName) {
    return 'How much room $modelName has to improvise. This only affects new responses.';
  }

  @override
  String get advancedSamplingHint =>
      'Turn on Advanced mode in Settings to set temperature, top-p and token budgets by hand.';

  @override
  String get sampling => 'Sampling';

  @override
  String get stylePreciseDetail =>
      'Sticks to the facts. Best for code and summaries.';

  @override
  String get styleBalancedDetail => 'The model\'s own defaults. Recommended.';

  @override
  String get styleCreativeDetail =>
      'Looser and more varied. Occasionally wrong.';

  @override
  String selectedOption(String name) {
    return '$name selected';
  }

  @override
  String get noTunableProfile =>
      'This model has no tunable profile on this build.';

  @override
  String get settingsLoadFailed => 'Couldn’t load settings.';

  @override
  String get samplingTemperature => 'Temperature';

  @override
  String get samplingTopP => 'Top-p';

  @override
  String get samplingTopK => 'Top-k';

  @override
  String get off => 'Off';

  @override
  String get maxTokens => 'Max tokens';

  @override
  String get contextLength => 'Context length';

  @override
  String styleSource(String style) {
    return '· $style';
  }

  @override
  String get defaultSource => '· default';

  @override
  String get tokenBudgetFootnote =>
      'Token budgets always leave 512 context tokens free for the prompt.';

  @override
  String get pinnedTokenBudgetFootnote =>
      'Token budgets always leave 512 context tokens free for the prompt. Thinking mode keeps this model\'s pinned sampling; budgets apply to both modes.';

  @override
  String get modelsLoadFailed => 'Couldn\'t load model state.';

  @override
  String get modelRuntimeFailed =>
      'The model runtime stopped unexpectedly. Try loading it again.';

  @override
  String get nothingInstalled => 'Nothing is installed yet.';

  @override
  String get nothingInstalledSimulated =>
      'Nothing is installed yet. Downloads here are a deterministic simulation.';

  @override
  String get runtime => 'Runtime';

  @override
  String get customRepository => 'Custom repository';

  @override
  String get none => 'None';

  @override
  String get noneSimulatedInference => 'None · simulated inference';

  @override
  String get unloadRuntime => 'Unload Runtime';

  @override
  String get loadRuntime => 'Load Runtime';

  @override
  String get unloadSimulatedRuntime => 'Unload Simulated Runtime';

  @override
  String get loadSimulatedRuntime => 'Load Simulated Runtime';

  @override
  String get modelSaveFailed => 'Couldn’t save the model. Try again.';

  @override
  String get modelAdded => 'Model added';

  @override
  String get repositoryMalformedIdentifier =>
      'Enter a public repository as owner/name, for example unsloth/gemma-4-E2B-it-qat-GGUF.';

  @override
  String get repositoryNotFoundOrPrivate =>
      'That repository could not be read. Check the name, and note that private repositories are not supported.';

  @override
  String get repositoryGated =>
      'That repository requires accepting its licence on Hugging Face. Gated repositories are not supported.';

  @override
  String get repositoryDisabled =>
      'That repository has been disabled on Hugging Face.';

  @override
  String get repositoryRateLimited =>
      'Hugging Face is rate limiting this device. Try again shortly.';

  @override
  String get repositoryNetwork =>
      'Could not reach Hugging Face. Check your connection and try again.';

  @override
  String get repositoryMalformedMetadata =>
      'Hugging Face returned something unexpected for that repository. Try again shortly.';

  @override
  String get repositoryUnsafePath =>
      'That repository contains a file path this app will not write.';

  @override
  String get repositoryNoWeights =>
      'No weights this engine can load were found in that repository.';

  @override
  String get repositoryShardedWeights =>
      'That model is split across multiple weight files, which is not supported yet. Choose a single-file version.';

  @override
  String get repositoryUnsafeWeightFormat =>
      'That repository publishes its weights in a format this app will not load. Only safetensors and GGUF are supported.';

  @override
  String get repositoryMissingRequiredFile =>
      'That repository is missing files the engine needs to load it.';

  @override
  String get repositoryInconsistentMetadata =>
      'That repository’s file listing disagrees with itself, so it cannot be pinned safely.';

  @override
  String get repositoryUnsupportedArchitecture =>
      'This version of Golem cannot run that model architecture.';

  @override
  String get repositoryHeaderTooLarge =>
      'That model’s metadata is larger than this app will read.';

  @override
  String get repositoryDuplicateEntry =>
      'That repository has already been added.';

  @override
  String get repositoryRevisionPlaceholder =>
      'main — or a branch, tag, or commit';

  @override
  String get unknownTemplateWarning =>
      'This will download and can be deleted, but Golem cannot prompt it: its chat template is not one this version recognizes.';

  @override
  String get simulatedRepositoryDetail =>
      'This build simulates downloads, so the revision and size below are synthesized rather than read from Hugging Face.';

  @override
  String get publicRepositoryDetail =>
      'Only public repositories are supported. Nothing downloads until you have seen what resolving found.';

  @override
  String get readingRepository => 'Reading the repository…';

  @override
  String get chooseWeightFile =>
      'This repository holds several weight files. Choose the one to install:';

  @override
  String get notRecognized => 'Not recognized';

  @override
  String moreFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more files',
      one: '1 more file',
    );
    return '+ $_temp0';
  }

  @override
  String get addModel => 'Add model';

  @override
  String get resolveRepository => 'Resolve';

  @override
  String get activeBadge => 'ACTIVE';

  @override
  String modelStatusLabel(String modelName, String engine) {
    return '$modelName $engine status';
  }

  @override
  String downloadProgressLabel(String suffix) {
    return 'Download$suffix';
  }

  @override
  String verifyingFilesStatus(String suffix) {
    return 'Verifying files$suffix…';
  }

  @override
  String openRepository(String repository) {
    return 'Open $repository on Hugging Face';
  }

  @override
  String modelSizeAndFiles(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$size · $_temp0';
  }

  @override
  String measuredSimulated(String rate) {
    return '$rate tok/s · simulated';
  }

  @override
  String measuredOnPhone(String rate) {
    return '$rate tok/s on this phone';
  }

  @override
  String get measured => 'Measured';

  @override
  String downloadSizeAction(String size) {
    return 'Download · $size';
  }

  @override
  String get cancelAndDiscard => 'Cancel and Discard';

  @override
  String get deleteDownload => 'Delete Download';

  @override
  String get notDownloaded => 'Not downloaded';

  @override
  String downloadingAmountStatus(
    String downloaded,
    String total,
    String suffix,
  ) {
    return 'Downloading $downloaded of $total$suffix';
  }

  @override
  String pausedAtStatus(String downloaded, String suffix) {
    return 'Paused at $downloaded$suffix';
  }

  @override
  String verifyingStatus(String suffix) {
    return 'Verifying$suffix';
  }

  @override
  String installedVerifiedStatus(String suffix) {
    return 'Installed and verified$suffix';
  }

  @override
  String get unloaded => 'Unloaded';

  @override
  String get loading => 'Loading…';

  @override
  String get loadingSimulation => 'Loading simulation…';

  @override
  String get readySimulated => 'Ready · simulated';

  @override
  String get stopped => 'Stopped';

  @override
  String get benchmark => 'Benchmark';

  @override
  String get protocol => 'Protocol';

  @override
  String get prompt => 'Prompt';

  @override
  String get run => 'Run';

  @override
  String get warmup => 'Warmup';

  @override
  String get maximumOutput => 'Maximum output';

  @override
  String get seed => 'Seed';

  @override
  String get benchmarkProtocolDetail =>
      'Uses the tracked production prompt fixture. Output and timing are deterministic simulations only.';

  @override
  String get simulationStatus => 'Simulation status';

  @override
  String get thermal => 'Thermal';

  @override
  String get notMeasured => 'Not measured';

  @override
  String get lowPowerMode => 'Low Power Mode';

  @override
  String get notRead => 'Not read';

  @override
  String get hardwareValidation => 'Hardware validation';

  @override
  String get no => 'No';

  @override
  String get stopSimulatedBenchmark => 'Stop Simulated Benchmark';

  @override
  String get runSimulatedBenchmark => 'Run Simulated Benchmark';

  @override
  String get generatingDeterministicResult =>
      'Generating deterministic result…';

  @override
  String get simulatedResult => 'Simulated result';

  @override
  String get benchmarkPrompt => 'Benchmark prompt';

  @override
  String get shortExplanation => 'Short explanation';

  @override
  String get mediumReview => 'Medium review';

  @override
  String get longSynthesis => 'Long synthesis';

  @override
  String get simulatedNotValidated => 'SIMULATED · NOT HARDWARE VALIDATED';

  @override
  String get generated => 'Generated';

  @override
  String tokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '1 token',
    );
    return '$_temp0';
  }

  @override
  String get decode => 'Decode';

  @override
  String tokenRate(String rate) {
    return '$rate tok/s';
  }

  @override
  String get peakMemory => 'Peak memory';

  @override
  String get simulatedEndOfTurn => 'Simulated end of turn';

  @override
  String get benchmarkExportTitle => 'Golem simulated benchmark';

  @override
  String get benchmarkExportText =>
      'Simulated benchmark JSON — not hardware validated.';

  @override
  String get exportSimulatedJson => 'Export Simulated JSON';

  @override
  String get benchmarkSimulationNotice =>
      'This screen simulates the workflow. It does not measure this device.';

  @override
  String get deviceMissingInstructionSet =>
      'This device’s processor is missing an instruction set the local engine needs, so it cannot run models here.';

  @override
  String get deviceBelowMemoryFloor =>
      'This device has less memory than the smallest model Golem ships needs to run, so downloads are turned off here. Your chats and settings are unaffected.';

  @override
  String outOfMemoryAtContext(int tokens) {
    final intl.NumberFormat tokensNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String tokensString = tokensNumberFormat.format(tokens);

    return 'Ran out of memory at $tokensString tokens. Lower the context length or pick a smaller model.';
  }

  @override
  String get defaultLowercase => 'default';

  @override
  String get stylePreciseLowercase => 'precise';

  @override
  String get styleBalancedLowercase => 'balanced';

  @override
  String get styleCreativeLowercase => 'creative';

  @override
  String hiddenEngineModels(int count, String engine) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count other models are built for a different engine and are not listed.',
      one: '1 other model is built for a different engine and is not listed.',
    );
    return '$_temp0 This build runs $engine.';
  }

  @override
  String get notAvailableOnDevice => 'Not available on this device.';

  @override
  String get pinnedByBuild => 'Pinned by this build.';

  @override
  String otherEngineAdmission(String engine) {
    return 'This build uses the $engine engine.';
  }

  @override
  String get memoryUnreadableLighterModel =>
      'Golem could not read this phone’s memory, so it ships the lighter model here.';

  @override
  String get needsMoreReportedMemory =>
      'Needs more memory than this phone reports.';

  @override
  String get modelsUnavailableOnDevice =>
      'Models are unavailable on this device.';

  @override
  String get unresolvedRepositoryReason =>
      'This repository has not been resolved against Hugging Face, so its files are unknown. Add it again to resolve it.';

  @override
  String installedOtherEngine(String buildEngine, String modelEngine) {
    return 'Installed, but this build runs $buildEngine and cannot load $modelEngine models.';
  }

  @override
  String get unrecognizedChatTemplate =>
      'Installed, but Golem does not recognize this model’s chat template, so it cannot prompt it.';

  @override
  String get pickAfterDownload => 'Pick it once the download finishes.';

  @override
  String get resumeForChat => 'Resume the download to use it in this chat.';

  @override
  String get unfinishedDownload =>
      'The download did not finish, so it cannot be picked yet.';

  @override
  String get downloadForChat => 'Download it to use it in this chat.';

  @override
  String get customModelSummary => 'Added by you from Hugging Face.';

  @override
  String get anotherModelDownloading => 'Another model is downloading.';

  @override
  String downloadingStatus(String suffix) {
    return 'Downloading$suffix';
  }

  @override
  String verifyingFilesPicker(String suffix) {
    return 'Verifying files$suffix';
  }

  @override
  String pausedDownloadAmount(String downloaded, String total, String suffix) {
    return 'Paused at $downloaded of $total$suffix.';
  }

  @override
  String get readsPictures => 'reads pictures';

  @override
  String modelSpeedSimulated(String rate) {
    return '$rate tok/s simulated';
  }

  @override
  String modelSpeedOnPhone(String rate) {
    return '$rate tok/s on this phone';
  }

  @override
  String get buildDefaultModel => 'This build’s default model.';

  @override
  String get lighterModelUnknownMemory =>
      'The lighter model, picked because this phone’s memory could not be read.';

  @override
  String get largerModelFits =>
      'This phone has the memory for the larger model.';

  @override
  String get sizedForPhone => 'Sized to fit this phone’s memory.';

  @override
  String sideloadPreventsSwitch(String modelName) {
    return 'This build runs $modelName from a path it pins, so this chat cannot switch models.';
  }

  @override
  String get modelLoadsNextMessage =>
      'The model you pick loads with your next message.';

  @override
  String get selectedModel => 'Selected model';

  @override
  String get manageModels => 'Manage models';

  @override
  String get gemmaModelSummary =>
      'A balanced all-rounder for everyday writing, summarising and light code.';

  @override
  String get qwenTwoBModelSummary =>
      'The smallest and quickest to answer. Best for short questions, and for phones with less memory to spare.';

  @override
  String get qwenFourBModelSummary =>
      'Leans towards code and maths, and can think a problem through before it answers.';
}
