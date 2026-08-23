// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'Golem';

  @override
  String get startingUp => '起動中';

  @override
  String get launchTakingLonger => '起動に通常より時間がかかっています。';

  @override
  String get launchStorageUnavailable => 'Golemはこの端末のストレージにアクセスできませんでした。';

  @override
  String get launchInvalidConfiguration => 'このGolemのビルドは正しく構成されていないため、起動できません。';

  @override
  String get launchUnknownFailure => 'Golemは起動を完了できませんでした。';

  @override
  String get tryAgain => 'もう一度試す';

  @override
  String get back => '戻る';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get delete => '削除';

  @override
  String get download => 'ダウンロード';

  @override
  String get pause => '一時停止';

  @override
  String get resume => '再開';

  @override
  String get retry => '再試行';

  @override
  String get reset => 'リセット';

  @override
  String get done => '完了';

  @override
  String get settingsTitle => '設定';

  @override
  String get chatTitle => 'チャット';

  @override
  String get settingsSectionModel => 'モデル';

  @override
  String get settingsSectionApp => 'アプリ';

  @override
  String get settingsSectionAbout => '情報';

  @override
  String get settingsModel => 'モデル';

  @override
  String get settingsResponseStyle => '応答スタイル';

  @override
  String get settingsSystemPrompt => 'システムプロンプト';

  @override
  String get settingsAppearance => '外観';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsPrivacyData => 'プライバシーとデータ';

  @override
  String get settingsStorage => 'ストレージ';

  @override
  String get settingsBenchmark => 'ベンチマーク';

  @override
  String get settingsModelAttribution => 'モデルの帰属情報';

  @override
  String get settingsOpenSourceLicenses => 'オープンソースライセンス';

  @override
  String get settingsAboutGolem => 'Golemについて';

  @override
  String get languageSystem => 'システムのデフォルト';

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
  String get languageSystemDetail => 'この端末で選択されている言語を使用します。';

  @override
  String get languageSaveFailed => '言語を保存できませんでした。以前の選択に戻しました。';

  @override
  String get preferencesLoadFailed => '環境設定を読み込めませんでした。';

  @override
  String get themeSystem => 'システム';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get showInferenceMetrics => '推論メトリクスを表示';

  @override
  String get alwaysExpandReasoning => '思考を常に展開';

  @override
  String get hapticsOnSend => '送信時に振動';

  @override
  String get textSize => '文字サイズ';

  @override
  String get newChat => '新しいチャット';

  @override
  String get searchChats => 'チャットを検索';

  @override
  String get settings => '設定';

  @override
  String get rename => '名前を変更';

  @override
  String get renameChat => 'チャット名を変更';

  @override
  String get shareTranscript => '会話記録を共有';

  @override
  String get pinToTop => '先頭に固定';

  @override
  String get unpin => '固定を解除';

  @override
  String get deleteChatTitle => 'チャットを削除しますか？';

  @override
  String get deleteChatMessage => 'このチャットは端末から削除されます。';

  @override
  String get today => '今日';

  @override
  String get yesterday => '昨日';

  @override
  String get previousSevenDays => '過去7日間';

  @override
  String get older => 'それ以前';

  @override
  String get noChatsYet => 'チャットはまだありません';

  @override
  String get noSearchResults => 'チャットが見つかりません';

  @override
  String get jumpToLatest => '最新のメッセージへ移動';

  @override
  String get messagePlaceholder => 'Golemにメッセージを送信';

  @override
  String get sendMessage => 'メッセージを送信';

  @override
  String get stopGenerating => '生成を停止';

  @override
  String get attach => '添付';

  @override
  String get copy => 'コピー';

  @override
  String get copied => 'コピーしました';

  @override
  String get reasoning => '思考';

  @override
  String get showReasoning => '思考を表示';

  @override
  String get hideReasoning => '思考を非表示';

  @override
  String get thinking => '思考中…';

  @override
  String get model => 'モデル';

  @override
  String get models => 'モデル';

  @override
  String get allModels => 'すべて';

  @override
  String get installedModels => 'インストール済み';

  @override
  String get recommended => 'おすすめ';

  @override
  String get activeModel => '使用中のモデル';

  @override
  String get state => '状態';

  @override
  String get revision => 'リビジョン';

  @override
  String get quantization => '量子化';

  @override
  String get size => 'サイズ';

  @override
  String get promptProfile => 'プロンプトプロファイル';

  @override
  String get repository => 'リポジトリ';

  @override
  String get context => 'コンテキスト';

  @override
  String get input => '入力';

  @override
  String get textOnly => 'テキスト';

  @override
  String get textAndImages => 'テキスト + 画像';

  @override
  String get downloadProgress => 'ダウンロードの進行状況';

  @override
  String get keep => '保持';

  @override
  String deleteModelTitle(String modelName) {
    return '$modelNameを削除しますか？';
  }

  @override
  String get deleteModelMessage =>
      'ダウンロードしたファイルはこの端末から削除されます。後でもう一度ダウンロードできます。';

  @override
  String downloadSize(String size) {
    return 'ダウンロード · $size';
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
      other: '$count件のチャット',
      zero: 'チャットはありません',
    );
    return '$_temp0';
  }

  @override
  String get defaultValue => 'デフォルト';

  @override
  String get customValue => 'カスタム';

  @override
  String get stylePrecise => '正確';

  @override
  String get styleBalanced => 'バランス';

  @override
  String get styleCreative => '創造的';

  @override
  String get advancedMode => '詳細モード';

  @override
  String get advancedModeDetail =>
      'サンプリング設定、カスタムシステムプロンプト、任意のHugging Faceリポジトリの手動読み込み。';

  @override
  String get aboutLegal => '情報と法的事項';

  @override
  String get openSourcePrivacyFootnote =>
      'Golemはオープンソースです。この画面から外部へデータが送信されることはありません。';

  @override
  String get simulatedInferenceBanner => '推論シミュレーション · ハードウェア未検証';

  @override
  String get theme => 'テーマ';

  @override
  String get inTranscript => '会話記録での表示';

  @override
  String get textPreview => 'ちょうどよい見え方です。';

  @override
  String percentValue(int value) {
    return '$valueパーセント';
  }

  @override
  String languageSelected(String language) {
    return '$languageを選択中';
  }

  @override
  String get modelDownloadsSimulated =>
      'モデルのダウンロードは固定カタログの決定論的シミュレーションです。ネットワークにはアクセスしません。';

  @override
  String get modelDownloadsReal =>
      'モデルのダウンロードでは、固定されたアーティファクトをHugging FaceからHTTPSで取得します。';

  @override
  String get inferenceSimulated =>
      '推論は決定論的なUIシミュレーションです。モデルの重み、エンジン、ハードウェア測定は含まれません。';

  @override
  String get inferenceLocal => '推論は、使用中のモデルとこの端末のローカルエンジンで実行されます。';

  @override
  String get networkPrivacyStatement =>
      'それ以外にネットワークを使うことはなく、Golemがほかのアプリのデータを読み取ることもありません。';

  @override
  String get saveFailed => '保存できませんでした。もう一度お試しください。';

  @override
  String get firstRunTagline => '外部と通信しないチャットアプリ。';

  @override
  String get firstRunIntroduction =>
      'Golemはオープンモデルを1つ端末に読み込み、その場で実行します。アカウントもサーバーも不要で、会話のコピーがほかの場所に保存されることもありません。';

  @override
  String get promisePrivateTitle => '端末の外には何も出ません';

  @override
  String get promisePrivateDetail => 'メッセージはGolemのプライベートストレージに保存されます。';

  @override
  String get promiseOfflineTitle => 'オフラインで動作';

  @override
  String get promiseOfflineDetail => 'モデルを一度ダウンロードすれば、それで完了です。';

  @override
  String get promiseControlTitle => '必要ならすべて調整可能';

  @override
  String get promiseControlDetail => '応答スタイル、システムプロンプト、サンプリング設定。';

  @override
  String get getStarted => '始める';

  @override
  String get oneModelHeadline => 'モデルは1つ。設定は不要です。';

  @override
  String get noCompatibleModel => 'このビルドに対応するモデルが見つかりませんでした。';

  @override
  String modelOfflineIntroduction(String modelName) {
    return 'Golemは$modelNameを一度ダウンロードすると、チャットへの応答にネットワークを必要としません。';
  }

  @override
  String get downloadUnavailable => 'ダウンロードできません';

  @override
  String get chooseDifferentModel => '別のモデルを選択';

  @override
  String tokensThousands(int count) {
    return '${count}Kトークン';
  }

  @override
  String get featuredModelDetail =>
      '日常的な文章、要約、簡単なコードに適しています。モデルの速度はこの端末によって異なり、実行前には推定されません。';

  @override
  String get allModelsTitle => 'すべてのモデル';

  @override
  String get catalogSimulationDetail =>
      'このビルドでは固定カタログ全体を表示します。ダウンロードとモデル実行はシミュレーションです。';

  @override
  String get catalogDeviceDetail =>
      'このビルドのエンジンに対応するモデルを選択できます。大きいモデルには推奨端末クラスが必要です。';

  @override
  String get chooseModel => 'モデルを選択';

  @override
  String get startChatting => 'チャットを始める';

  @override
  String get pauseDownload => 'ダウンロードを一時停止';

  @override
  String get retryDownload => 'ダウンロードを再試行';

  @override
  String get resumeDownload => 'ダウンロードを再開';

  @override
  String modelReady(String modelName) {
    return '$modelNameの準備ができました';
  }

  @override
  String modelVerifying(String modelName) {
    return '$modelNameを検証中';
  }

  @override
  String modelDownloading(String modelName) {
    return '$modelNameをダウンロード中';
  }

  @override
  String get selectedCatalogUnavailable => '選択したカタログ項目は利用できません。';

  @override
  String get downloadFailed => 'ダウンロードに失敗しました。もう一度試すことができます。';

  @override
  String downloadInsufficientStorage(String required, String available) {
    return 'モデルには$requiredの空き容量が必要ですが、利用できるのは$availableのみです。';
  }

  @override
  String downloadHashVerificationFailed(String fileName) {
    return '$fileNameの整合性を確認できませんでした。ダウンロードを再試行してください。';
  }

  @override
  String downloadUnexpectedFileSize(String fileName) {
    return '$fileNameのサイズが正しくありません。ダウンロードを再試行してください。';
  }

  @override
  String get downloadSimulationComplete => '決定論的なシミュレーションが完了しました。重みは保存されていません。';

  @override
  String get downloadComplete => 'この端末で検証されました。Golemはネットワーク接続なしで応答できます。';

  @override
  String downloadAmount(String downloaded, String total) {
    return '$total中$downloaded';
  }

  @override
  String verifiedAmount(String verified, String total) {
    return '$total中$verifiedを検証済み';
  }

  @override
  String get downloadNote => 'Golem を開いたままにしてください。バックグラウンドではダウンロードが遅くなります。';

  @override
  String etaAboutMinutesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '残り約$count分',
    );
    return '$_temp0';
  }

  @override
  String etaAboutHoursLeft(int count) {
    return '残り約$count時間';
  }

  @override
  String etaAboutHoursMinutesLeft(int hours, int minutes) {
    return '残り約$hours時間$minutes分';
  }

  @override
  String amountLeft(String amount) {
    return '残り $amount';
  }

  @override
  String stoppedAtPercent(int percent) {
    return '$percent% で停止しました';
  }

  @override
  String rateMbs(String rate) {
    return '$rate MB/s';
  }

  @override
  String get paused => '一時停止中';

  @override
  String get gettingGolemReady => 'Golem を準備しています';

  @override
  String get oneDownloadPitch => '今回のダウンロードが済めば、Golem はこの端末上だけで応答します。';

  @override
  String downloadedAmount(String amount) {
    return 'ダウンロード済み · $amount';
  }

  @override
  String get privacyFootnote => 'モデルはこの端末に保存されます。入力した内容が送信されることはありません。';

  @override
  String get chatsStayAvailable => 'チャットは引き続き利用できます。';

  @override
  String get modelsUnavailableGeneric => 'Golemはこの端末でモデルを実行できません。';

  @override
  String get unsupportedFeaturesRemain =>
      'モデルはダウンロードされません。チャット、履歴、設定、エクスポートは引き続き利用できます。';

  @override
  String get continueToGolem => 'Golemへ進む';

  @override
  String get modelChoiceSaveFailed => 'モデルの選択を保存できませんでした。もう一度お試しください。';

  @override
  String get setupSaveFailed => 'Golemは初期設定を保存できませんでした。もう一度お試しください。';

  @override
  String get simulateDownloadTitle => 'このダウンロードをシミュレーションしますか？';

  @override
  String get downloadModelTitle => 'このモデルをダウンロードしますか？';

  @override
  String simulateDownloadMessage(String modelName, String size) {
    return '$modelNameは$sizeのダウンロードとして表示されています。このシミュレーションはネットワークを使わず、モデルの重みも保存しません。';
  }

  @override
  String downloadModelMessage(String modelName, String size) {
    return '$modelNameはHugging Faceから$sizeをダウンロードします。その容量に加えて500 MiBの空き容量を確保してください。Wi-Fiを推奨します。モバイルデータ通信料がかかる場合があります。';
  }

  @override
  String get notNow => '今はしない';

  @override
  String get simulate => 'シミュレーション';

  @override
  String finishModelSetup(String modelName) {
    return '$modelNameの設定を完了';
  }

  @override
  String modelDownloadPaused(String modelName) {
    return '$modelNameのダウンロードを一時停止しました';
  }

  @override
  String modelNeedsAttention(String modelName) {
    return '$modelNameを確認してください';
  }

  @override
  String get setupDownloadPrompt => 'Golemを使用する前に、選択したモデルをダウンロードして検証してください。';

  @override
  String get simulatedDownloadShort => '決定論的なシミュレーション。ネットワークも重みも使用しません。';

  @override
  String get downloadBeforeSending => 'メッセージを送信するには、モデルのダウンロードと検証を完了する必要があります。';

  @override
  String get resumeProgressKept => '準備ができたら再開してください。現在の進行状況は保持されます。';

  @override
  String get checkingDownloadedFiles => '実行できるようになる前に、ダウンロードしたファイルを確認しています。';

  @override
  String get downloadFailedChatsSafe => 'ダウンロードに失敗しました。チャットには影響ありません。';

  @override
  String get ready => '準備完了。';

  @override
  String get conversationsAppearHere => '会話はここに表示されます。';

  @override
  String get pinned => '固定済み';

  @override
  String get unpinned => '固定解除済み';

  @override
  String get earlier => 'それ以前';

  @override
  String get conversationActions => '会話の操作';

  @override
  String deleteNamedChatMessage(String title) {
    return '「$title」とそのすべてのメッセージがこの端末から削除されます。';
  }

  @override
  String get chatDeleted => 'チャットを削除しました';

  @override
  String storageUsedAndFree(String used, String free) {
    return '使用中$used · 空き容量$free';
  }

  @override
  String get closeConversations => '会話を閉じる';

  @override
  String get discard => '破棄';

  @override
  String downloadNamedModel(String modelName, String size) {
    return '$modelName（$size）をダウンロード';
  }

  @override
  String get addToChat => 'このチャットに追加';

  @override
  String get photoLibrary => '写真ライブラリ';

  @override
  String get takePhoto => '写真を撮る';

  @override
  String get files => 'ファイル';

  @override
  String imagesPrivateDetail(String modelName) {
    return '画像はこの端末で読み取られます。$modelNameは画像を参照できますが、外部にはアップロードされません。';
  }

  @override
  String imagesUnsupportedDetail(String modelName) {
    return '$modelNameはテキストのみを処理します。画像を添付するには、画像を読み取れるモデルに切り替えてください。';
  }

  @override
  String get unsupportedImageType =>
      'このファイル形式には対応していません。JPEG、PNG、またはWebP画像を使用してください。';

  @override
  String get imageTooLarge => 'この画像は大きすぎて添付できません。';

  @override
  String get imageUnreadable => 'この画像を読み取れませんでした。';

  @override
  String get imagePermissionDenied =>
      '写真を添付するには、Golemにカメラと写真へのアクセスが必要です。設定でアクセスを有効にしてください。';

  @override
  String get imageAddFailed => 'この写真を追加できませんでした。';

  @override
  String get removeAttachedImage => '添付画像を削除';

  @override
  String get modelForChat => 'このチャットのモデル';

  @override
  String get reasoningOn => '思考オン';

  @override
  String get reasoningOff => '思考オフ';

  @override
  String get think => '考える';

  @override
  String get startPrivateConversation => 'プライベートな会話を始める';

  @override
  String get whatAreWeBuilding => '何を作りましょうか？';

  @override
  String get cannotRunModelsHere => 'ここではGolemのモデルを実行できません';

  @override
  String simulatedModelPrivacy(String modelName) {
    return 'このプレビューでは、この端末上の$modelNameをシミュレーションします。ここに入力した内容はどこにも送信されません。';
  }

  @override
  String localModelPrivacy(String modelName) {
    return '$modelNameはこの端末に読み込まれ、実行されています。ここに入力した内容はどこにも送信されません。';
  }

  @override
  String downloadedModelPrivacy(String modelName) {
    return '$modelNameはこの端末にダウンロードされ、検証済みです。メッセージを送信すると読み込まれます。ここに入力した内容はどこにも送信されません。';
  }

  @override
  String validatedModelPrivacy(String modelName) {
    return '$modelNameはこのセッション用に検証され、この端末上でのみ実行されます。ここに入力した内容はどこにも送信されません。';
  }

  @override
  String get starterDraftReply => '返信を作成';

  @override
  String get starterDraftReplyPrompt => 'このメッセージへの返信を作成してください：';

  @override
  String get starterExplain => '説明してもらう';

  @override
  String get starterExplainPrompt => '簡単に説明してください：';

  @override
  String get starterRewrite => '文章を書き直す';

  @override
  String get starterRewritePrompt => '読みやすく書き直してください：';

  @override
  String get starterSummarise => 'メモを要約';

  @override
  String get starterSummarisePrompt => 'このメモを要約してください：';

  @override
  String get noChatsMatchSearch => '検索条件に一致するチャットはありません。';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'チャット$count件',
    );
    return '$_temp0';
  }

  @override
  String get localSearchPrivacy => '検索はローカルデータベースで実行されます。インデックスはアップロードされません。';

  @override
  String searchMatchSummary(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件一致',
    );
    return '$date · $_temp0';
  }

  @override
  String stoppedAfterTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countトークンで停止',
    );
    return '$_temp0';
  }

  @override
  String get copyMessage => 'メッセージをコピー';

  @override
  String get regenerateResponse => '応答を再生成';

  @override
  String get shareMessage => 'メッセージを共有';

  @override
  String get messageActions => 'メッセージの操作';

  @override
  String get regenerate => '再生成';

  @override
  String get branchFromHere => 'ここから分岐';

  @override
  String get share => '共有';

  @override
  String get deleteMessage => 'メッセージを削除';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get newBranchStarted => '新しい分岐を開始しました';

  @override
  String get yourMessage => 'あなたのメッセージ';

  @override
  String get golemResponse => 'Golemの応答';

  @override
  String get editAndRetry => '編集して再試行';

  @override
  String get editMessage => 'メッセージを編集';

  @override
  String get userSpeaker => 'あなた';

  @override
  String get assistantSpeaker => 'Golem';

  @override
  String get saveAndRegenerate => '保存して再生成';

  @override
  String get generationFailed => '応答の生成中に問題が発生しました。';

  @override
  String get attachmentUnavailableFailure =>
      'この会話の画像の1つが利用できなくなりました。このメッセージを削除して、もう一度送信してください。';

  @override
  String get modelUnavailableFailure =>
      'このチャットのモデルは、このバージョンのGolemでは利用できません。続けるには別のモデルを選択してください。';

  @override
  String get unsupportedModelFailure =>
      'Golemはこのモデルのチャットテンプレートまたはファイルを使用できません。続けるには対応モデルを選択してください。';

  @override
  String get unsupportedImagesFailure =>
      'このモデルはメッセージ内の画像を読み取れません。メッセージを削除するか、画像を読み取れるモデルを選択してください。';

  @override
  String get invalidModelArtifactFailure =>
      'インストール済みモデルが見つからないか、破損しているか、このバージョンのGolemと互換性がありません。別のモデルを選択するか、再度ダウンロードしてください。';

  @override
  String get attachmentSaveFailed => 'この画像を保存できませんでした。もう一度添付してください。';

  @override
  String modelMissingForChat(String modelName) {
    return '$modelNameはまだこの端末にダウンロードされていません。このチャットで使用するにはダウンロードしてください。';
  }

  @override
  String get contextExhausted =>
      'この会話はモデルのコンテキストウィンドウに収まらないほど長くなっています。続けるには新しいチャットを開始してください。';

  @override
  String get outOfMemory => '生成中にモデルのメモリが不足しました。ほかのアプリを閉じて、もう一度お試しください。';

  @override
  String get insufficientMemory =>
      'このモデルを読み込むための空きメモリが不足しています。ほかのアプリを閉じるか、より小さいモデルを選択してください。';

  @override
  String get budgetExhausted =>
      'モデルは応答を生成する前にトークン上限を使い切りました。もう一度試すか、応答設定を調整してください。';

  @override
  String imageCountSentence(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' 画像$count件。',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String tokenRateSummary(String rate, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countトークン',
    );
    return '$rate tok/s · $_temp0';
  }

  @override
  String get aiDisclaimer => 'AIの応答は不正確な場合があります。重要な情報は確認してください。';

  @override
  String get privacyStatement =>
      'Golemにはアカウントがなく、解析データも送信しません。モデルのダウンロード後はネットワーク権限も破棄します。オプトアウトするものはありません。';

  @override
  String get onThisPhone => 'この端末上';

  @override
  String get saveChatHistory => 'チャット履歴を保存';

  @override
  String get saveHistoryOffDetail => 'オフにすると、アプリを閉じた時点ですべてのチャットが消去されます。';

  @override
  String get yourData => 'あなたのデータ';

  @override
  String get exportAllChats => 'すべてのチャットをエクスポート';

  @override
  String get deleteAllChats => 'すべてのチャットを削除';

  @override
  String get stopSavingChatsTitle => 'チャットの保存を停止しますか？';

  @override
  String get stopSavingChatsMessage =>
      'この端末に保存済みのチャットは今すぐ削除されます。開いているチャットはアプリを閉じるまで残りますが、新しい内容はディスクに書き込まれません。';

  @override
  String get keepSaving => '保存を続ける';

  @override
  String get stopAndDelete => '停止して削除';

  @override
  String get deleteSavedChatsFailed => '保存済みのチャットを削除できませんでした。もう一度お試しください。';

  @override
  String get chatsExportSubject => 'Golemチャットのエクスポート';

  @override
  String get deleteAllChatsTitle => 'すべてのチャットを削除しますか？';

  @override
  String get deleteAllChatsMessage =>
      'すべての会話がこの端末から削除されます。ダウンロード済みのモデルは保持されます。';

  @override
  String get chatsDeleted => 'チャットを削除しました';

  @override
  String get deleteChatsFailed => 'チャットを削除できませんでした。もう一度お試しください。';

  @override
  String get systemPromptDetail =>
      '会話より先に送信され、以降のすべての新しい応答に適用される指示です。モデルのデフォルト動作を使うには空欄にしてください。';

  @override
  String get systemPromptExample => '例：簡潔でわかりやすい言葉で回答してください。';

  @override
  String get resetToDefault => 'デフォルトに戻す';

  @override
  String get systemPromptLocalFootnote => 'プロンプトは両方のモデルに適用され、この端末に保存されます。';

  @override
  String get storageReadFailed => 'ストレージを読み取れませんでした。';

  @override
  String get downloadedModels => 'ダウンロード済みモデル';

  @override
  String get clearInferenceCache => '推論キャッシュを消去';

  @override
  String get modelDeletionFootnote => 'モデルを削除すると、すぐに空き容量が増えます。チャットは保持されます。';

  @override
  String get cacheCleared => 'キャッシュを消去しました';

  @override
  String storageFree(String size) {
    return '空き容量$size';
  }

  @override
  String storageModelsAmount(String size) {
    return 'モデル $size';
  }

  @override
  String storageChatsAmount(String size) {
    return 'チャット $size';
  }

  @override
  String storageImagesAmount(String size) {
    return '画像 $size';
  }

  @override
  String storageCacheAmount(String size) {
    return 'キャッシュ $size';
  }

  @override
  String get noDownloadedModels => 'ダウンロード済みのモデルはまだありません。';

  @override
  String get active => '使用中';

  @override
  String get partial => '一部';

  @override
  String deleteModelArtifactTitle(String modelName, String format) {
    return '$modelName · $formatを削除しますか？';
  }

  @override
  String deleteModelStorageMessage(String size) {
    return 'この端末から$sizeを削除します。モデルは後でもう一度ダウンロードできます。';
  }

  @override
  String megabytes(int value) {
    return '$value MB';
  }

  @override
  String get licensesIntroduction =>
      'Golemはオープンソースソフトウェアを使用しています。これらの通知には、Golemが同梱するネイティブエンジンと直接依存するパッケージが記載され、オフラインでも確認できます。';

  @override
  String licenseEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ライセンス項目$count件',
    );
    return '$_temp0';
  }

  @override
  String get licensesLoadFailed => 'ライセンスを読み込めませんでした。';

  @override
  String get licensesRetryDetail => '同梱ファイルはこの端末に残っています。もう一度読み込んでください。';

  @override
  String showLicenseFor(String name) {
    return '$nameのライセンスを表示';
  }

  @override
  String hideLicenseFor(String name) {
    return '$nameのライセンスを非表示';
  }

  @override
  String get modelAttributionIntroduction =>
      'Golemにはモデルの重みが含まれていません。ダウンロードを承認した後にのみ、ここに記載された正確なアーティファクトを取得します。';

  @override
  String get officialModelCard => '公式モデルカード';

  @override
  String get license => 'ライセンス';

  @override
  String get customRepositoryTerms =>
      '手動で追加したリポジトリには、配布元独自の条件が適用されます。Golemがそれらを認証または再配布することはありません。';

  @override
  String get startupFailed => '起動に失敗しました';

  @override
  String get startupCouldNotFinish => 'Golemは起動を完了できませんでした';

  @override
  String get preparingFirstRun => '初回設定を準備中';

  @override
  String get preparingSetup => '設定を準備中';

  @override
  String get startingOnDevice => 'この端末でGolemを起動中';

  @override
  String get gettingReady => '準備中';

  @override
  String get splashTagline => 'プライベート、ローカル、いつでも準備完了。';

  @override
  String get chatHistoryNotSaving =>
      'チャット履歴が保存されていません。アプリを閉じると最新の変更が失われる可能性があります。';

  @override
  String get saving => '保存中…';

  @override
  String get reasoningLive => '思考をリアルタイム表示';

  @override
  String get expanded => '展開済み';

  @override
  String get collapsed => '折りたたみ済み';

  @override
  String get reasoningLiveBadge => '思考 · リアルタイム';

  @override
  String generatingAtRate(String rate) {
    return '生成中 · $rate tok/s';
  }

  @override
  String get imageUnavailable => '画像は利用できなくなりました';

  @override
  String get loadingImage => '画像を読み込み中';

  @override
  String get golemResponding => 'Golemが応答中';

  @override
  String get responseFinished => '応答が完了しました';

  @override
  String get chatHistoryLoadFailed => 'チャット履歴を読み込めませんでした。';

  @override
  String get openConversations => '会話を開く';

  @override
  String get images => '画像';

  @override
  String get stop => '停止';

  @override
  String get send => '送信';

  @override
  String get copyCode => 'コードをコピー';

  @override
  String get code => 'コード';

  @override
  String get unsupportedDevice => '非対応の端末';

  @override
  String get simulated => 'シミュレーション';

  @override
  String get onDevice => '端末上';

  @override
  String get responseStyle => '応答スタイル';

  @override
  String responseStyleDescription(String modelName) {
    return '$modelNameが自由に表現できる度合いです。新しい応答にのみ影響します。';
  }

  @override
  String get advancedSamplingHint =>
      '設定で詳細モードをオンにすると、temperature、top-p、トークン上限を手動で指定できます。';

  @override
  String get sampling => 'サンプリング';

  @override
  String get stylePreciseDetail => '事実に忠実です。コードや要約に最適です。';

  @override
  String get styleBalancedDetail => 'モデル独自のデフォルトを使用します。おすすめです。';

  @override
  String get styleCreativeDetail => 'より自由で多様です。誤ることもあります。';

  @override
  String selectedOption(String name) {
    return '$nameを選択中';
  }

  @override
  String get noTunableProfile => 'このビルドには、このモデル用の調整可能なプロファイルがありません。';

  @override
  String get settingsLoadFailed => '設定を読み込めませんでした。';

  @override
  String get samplingTemperature => '温度';

  @override
  String get samplingTopP => 'Top-p';

  @override
  String get samplingTopK => 'Top-k';

  @override
  String get off => 'オフ';

  @override
  String get maxTokens => '最大トークン数';

  @override
  String get contextLength => 'コンテキスト長';

  @override
  String styleSource(String style) {
    return '· $style';
  }

  @override
  String get defaultSource => '· デフォルト';

  @override
  String get tokenBudgetFootnote => 'トークン上限では、プロンプト用に常に512コンテキストトークンを確保します。';

  @override
  String get pinnedTokenBudgetFootnote =>
      'トークン上限では、プロンプト用に常に512コンテキストトークンを確保します。思考モードではこのモデルの固定サンプリングを維持し、上限は両方のモードに適用されます。';

  @override
  String get modelsLoadFailed => 'モデルの状態を読み込めませんでした。';

  @override
  String get modelRuntimeFailed => 'モデルのランタイムが予期せず停止しました。もう一度読み込んでください。';

  @override
  String get nothingInstalled => 'まだ何もインストールされていません。';

  @override
  String get nothingInstalledSimulated =>
      'まだ何もインストールされていません。ここでのダウンロードは決定論的シミュレーションです。';

  @override
  String get runtime => 'ランタイム';

  @override
  String get customRepository => 'カスタムリポジトリ';

  @override
  String get none => 'なし';

  @override
  String get noneSimulatedInference => 'なし · 推論シミュレーション';

  @override
  String get unloadRuntime => 'ランタイムを解放';

  @override
  String get loadRuntime => 'ランタイムを読み込む';

  @override
  String get unloadSimulatedRuntime => 'シミュレーションランタイムを解放';

  @override
  String get loadSimulatedRuntime => 'シミュレーションランタイムを読み込む';

  @override
  String get modelSaveFailed => 'モデルを保存できませんでした。もう一度お試しください。';

  @override
  String get modelAdded => 'モデルを追加しました';

  @override
  String get repositoryMalformedIdentifier =>
      '公開リポジトリを所有者/名前の形式で入力してください。例：unsloth/gemma-4-E2B-it-qat-GGUF。';

  @override
  String get repositoryNotFoundOrPrivate =>
      'そのリポジトリを読み取れませんでした。名前を確認してください。非公開リポジトリには対応していません。';

  @override
  String get repositoryGated =>
      'そのリポジトリではHugging Face上でライセンスへの同意が必要です。アクセス制限付きリポジトリには対応していません。';

  @override
  String get repositoryDisabled => 'そのリポジトリはHugging Faceで無効になっています。';

  @override
  String get repositoryRateLimited =>
      'Hugging Faceがこの端末からのリクエストを制限しています。しばらくしてからもう一度お試しください。';

  @override
  String get repositoryNetwork =>
      'Hugging Faceに接続できませんでした。接続を確認して、もう一度お試しください。';

  @override
  String get repositoryMalformedMetadata =>
      'Hugging Faceからそのリポジトリについて予期しないデータが返されました。しばらくしてからもう一度お試しください。';

  @override
  String get repositoryUnsafePath => 'そのリポジトリには、このアプリが書き込まないファイルパスが含まれています。';

  @override
  String get repositoryNoWeights => 'そのリポジトリには、このエンジンで読み込める重みが見つかりませんでした。';

  @override
  String get repositoryShardedWeights =>
      'そのモデルは複数の重みファイルに分割されており、まだ対応していません。単一ファイル版を選択してください。';

  @override
  String get repositoryUnsafeWeightFormat =>
      'そのリポジトリの重みは、このアプリで読み込まない形式です。safetensorsとGGUFのみに対応しています。';

  @override
  String get repositoryMissingRequiredFile =>
      'そのリポジトリには、エンジンが読み込みに必要とするファイルがありません。';

  @override
  String get repositoryInconsistentMetadata =>
      'そのリポジトリのファイル一覧には矛盾があるため、安全に固定できません。';

  @override
  String get repositoryUnsupportedArchitecture =>
      'このバージョンのGolemでは、そのモデルアーキテクチャを実行できません。';

  @override
  String get repositoryHeaderTooLarge => 'そのモデルのメタデータは、このアプリが読み取る上限を超えています。';

  @override
  String get repositoryDuplicateEntry => 'そのリポジトリはすでに追加されています。';

  @override
  String get repositoryRevisionPlaceholder => 'main — またはブランチ、タグ、コミット';

  @override
  String get unknownTemplateWarning =>
      'ダウンロードと削除はできますが、Golemからプロンプトを送信できません。このバージョンでは、そのチャットテンプレートを認識できません。';

  @override
  String get simulatedRepositoryDetail =>
      'このビルドではダウンロードをシミュレーションするため、以下のリビジョンとサイズはHugging Faceから読み取らずに生成されます。';

  @override
  String get publicRepositoryDetail =>
      '公開リポジトリのみに対応しています。解決結果を確認するまで、何もダウンロードされません。';

  @override
  String get readingRepository => 'リポジトリを読み取り中…';

  @override
  String get chooseWeightFile =>
      'このリポジトリには複数の重みファイルがあります。インストールするファイルを選択してください：';

  @override
  String get notRecognized => '認識できません';

  @override
  String moreFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ほか$count件',
    );
    return '+ $_temp0';
  }

  @override
  String get addModel => 'モデルを追加';

  @override
  String get resolveRepository => '解決';

  @override
  String get activeBadge => '選択中';

  @override
  String get loadedBadge => '読込済み';

  @override
  String modelStatusLabel(String modelName, String engine) {
    return '$modelName $engineの状態';
  }

  @override
  String downloadProgressLabel(String suffix) {
    return 'ダウンロード$suffix';
  }

  @override
  String openRepository(String repository) {
    return 'Hugging Faceで$repositoryを開く';
  }

  @override
  String modelSizeAndFiles(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countファイル',
    );
    return '$size · $_temp0';
  }

  @override
  String measuredSimulated(String rate) {
    return '$rate tok/s · シミュレーション';
  }

  @override
  String measuredOnPhone(String rate) {
    return 'この端末で$rate tok/s';
  }

  @override
  String get measured => '測定済み';

  @override
  String downloadSizeAction(String size) {
    return 'ダウンロード · $size';
  }

  @override
  String get cancelAndDiscard => 'キャンセルして破棄';

  @override
  String get deleteDownload => 'ダウンロードを削除';

  @override
  String get notDownloaded => '未ダウンロード';

  @override
  String downloadingAmountStatus(
    String downloaded,
    String total,
    String suffix,
  ) {
    return '$total中$downloadedをダウンロード中$suffix';
  }

  @override
  String pausedAtStatus(String downloaded, String suffix) {
    return '$downloadedで一時停止$suffix';
  }

  @override
  String verifyingStatus(String suffix) {
    return '検証中$suffix';
  }

  @override
  String installedVerifiedStatus(String suffix) {
    return 'インストール・検証済み$suffix';
  }

  @override
  String get unloaded => '解放済み';

  @override
  String get loading => '読み込み中…';

  @override
  String get loadingSimulation => 'シミュレーションを読み込み中…';

  @override
  String get readySimulated => '準備完了 · シミュレーション';

  @override
  String get stopped => '停止済み';

  @override
  String get benchmark => 'ベンチマーク';

  @override
  String get protocol => 'プロトコル';

  @override
  String get prompt => 'プロンプト';

  @override
  String get run => '実行';

  @override
  String get warmup => 'ウォームアップ';

  @override
  String get maximumOutput => '最大出力';

  @override
  String get seed => 'シード';

  @override
  String get benchmarkProtocolDetail =>
      '記録された本番用プロンプトファイルを使用します。出力と時間は決定論的シミュレーションにすぎません。';

  @override
  String get simulationStatus => 'シミュレーションの状態';

  @override
  String get thermal => '温度状態';

  @override
  String get notMeasured => '未測定';

  @override
  String get lowPowerMode => '低電力モード';

  @override
  String get notRead => '未取得';

  @override
  String get hardwareValidation => 'ハードウェア検証';

  @override
  String get no => 'いいえ';

  @override
  String get stopSimulatedBenchmark => 'シミュレーションベンチマークを停止';

  @override
  String get runSimulatedBenchmark => 'シミュレーションベンチマークを実行';

  @override
  String get generatingDeterministicResult => '決定論的な結果を生成中…';

  @override
  String get simulatedResult => 'シミュレーション結果';

  @override
  String get benchmarkPrompt => 'ベンチマークプロンプト';

  @override
  String get shortExplanation => '短い説明';

  @override
  String get mediumReview => '中程度のレビュー';

  @override
  String get longSynthesis => '長い要約';

  @override
  String get simulatedNotValidated => 'シミュレーション · ハードウェア未検証';

  @override
  String get generated => '生成済み';

  @override
  String tokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countトークン',
    );
    return '$_temp0';
  }

  @override
  String get decode => 'デコード';

  @override
  String tokenRate(String rate) {
    return '$rate tok/s';
  }

  @override
  String get peakMemory => '最大メモリ';

  @override
  String get simulatedEndOfTurn => 'シミュレーションのターン終了';

  @override
  String get benchmarkExportTitle => 'Golemシミュレーションベンチマーク';

  @override
  String get benchmarkExportText => 'シミュレーションベンチマークJSON — ハードウェア未検証。';

  @override
  String get exportSimulatedJson => 'シミュレーションJSONをエクスポート';

  @override
  String get benchmarkSimulationNotice =>
      'この画面はワークフローをシミュレーションします。この端末を測定するものではありません。';

  @override
  String get deviceMissingInstructionSet =>
      'この端末のプロセッサにはローカルエンジンが必要とする命令セットがないため、ここではモデルを実行できません。';

  @override
  String get deviceBelowMemoryFloor =>
      'この端末のメモリは、Golemが提供する最小モデルの要件を満たさないため、ダウンロードは無効です。チャットや設定には影響しません。';

  @override
  String get deviceVirtualHardware =>
      'Golemはモデルを実機で実行します。シミュレーターやエミュレーターでは読み込めないため、ここではダウンロードを無効にしています。';

  @override
  String outOfMemoryAtContext(int tokens) {
    final intl.NumberFormat tokensNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String tokensString = tokensNumberFormat.format(tokens);

    return '$tokensStringトークンでメモリが不足しました。コンテキスト長を短くするか、より小さいモデルを選択してください。';
  }

  @override
  String get defaultLowercase => 'デフォルト';

  @override
  String get stylePreciseLowercase => '正確';

  @override
  String get styleBalancedLowercase => 'バランス';

  @override
  String get styleCreativeLowercase => '創造的';

  @override
  String hiddenEngineModels(int count, String engine) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '別のエンジン向けのモデルがほかに$count件あるため、一覧に表示されていません。',
    );
    return '$_temp0 このビルドでは$engineを実行します。';
  }

  @override
  String get notAvailableOnDevice => 'この端末では利用できません。';

  @override
  String get pinnedByBuild => 'このビルドによって固定されています。';

  @override
  String otherEngineAdmission(String engine) {
    return 'このビルドは$engineエンジンを使用します。';
  }

  @override
  String get memoryUnreadableLighterModel =>
      'Golemはこの端末のメモリを読み取れなかったため、軽量モデルを提供します。';

  @override
  String get needsMoreReportedMemory => 'この端末から報告された容量より多くのメモリが必要です。';

  @override
  String get modelsUnavailableOnDevice => 'この端末ではモデルを利用できません。';

  @override
  String get unresolvedRepositoryReason =>
      'このリポジトリはHugging Faceに対して解決されていないため、ファイルが不明です。もう一度追加して解決してください。';

  @override
  String installedOtherEngine(String buildEngine, String modelEngine) {
    return 'インストール済みですが、このビルドは$buildEngineを実行するため、$modelEngineモデルを読み込めません。';
  }

  @override
  String get unrecognizedChatTemplate =>
      'インストール済みですが、Golemがこのモデルのチャットテンプレートを認識できないため、プロンプトを送信できません。';

  @override
  String get pickAfterDownload => 'ダウンロード完了後に選択してください。';

  @override
  String get resumeForChat => 'このチャットで使用するにはダウンロードを再開してください。';

  @override
  String get unfinishedDownload => 'ダウンロードが完了していないため、まだ選択できません。';

  @override
  String get downloadForChat => 'このチャットで使用するにはダウンロードしてください。';

  @override
  String get customModelSummary => 'Hugging Faceから追加したモデルです。';

  @override
  String get anotherModelDownloading => '別のモデルをダウンロード中です。';

  @override
  String downloadingStatus(String suffix) {
    return 'ダウンロード中$suffix';
  }

  @override
  String verifyingFilesPicker(String suffix) {
    return 'ファイルを検証中$suffix';
  }

  @override
  String pausedDownloadAmount(String downloaded, String total, String suffix) {
    return '$total中$downloadedで一時停止$suffix。';
  }

  @override
  String get readsPictures => '画像対応';

  @override
  String modelSpeedSimulated(String rate) {
    return '$rate tok/s（シミュレーション）';
  }

  @override
  String modelSpeedOnPhone(String rate) {
    return 'この端末で$rate tok/s';
  }

  @override
  String get buildDefaultModel => 'このビルドのデフォルトモデル。';

  @override
  String get lighterModelUnknownMemory => 'この端末のメモリを読み取れなかったため選択された軽量モデル。';

  @override
  String get largerModelFits => 'この端末には大きいモデルを実行できるメモリがあります。';

  @override
  String get sizedForPhone => 'この端末のメモリに合うサイズです。';

  @override
  String sideloadPreventsSwitch(String modelName) {
    return 'このビルドは固定パスから$modelNameを実行するため、このチャットではモデルを切り替えられません。';
  }

  @override
  String get modelLoadsNextMessage => '選択したモデルは次のメッセージで読み込まれます。';

  @override
  String get selectedModel => '選択中のモデル';

  @override
  String get manageModels => 'モデルを管理';

  @override
  String get gemmaModelSummary => '日常的な文章、要約、簡単なコードに適した、バランスのよい汎用モデルです。';

  @override
  String get qwenTwoBModelSummary => '最も小さく、すばやく応答します。短い質問や、空きメモリの少ない端末に最適です。';

  @override
  String get qwenFourBModelSummary => 'コードと数学を得意とし、応答する前に問題を考えることができます。';
}
