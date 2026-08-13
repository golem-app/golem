// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'Golem';

  @override
  String get startingUp => '시작하는 중';

  @override
  String get launchTakingLonger => '시작하는 데 예상보다 오래 걸리고 있습니다.';

  @override
  String get launchStorageUnavailable => 'Golem이 이 기기의 저장 공간에 접근할 수 없습니다.';

  @override
  String get launchInvalidConfiguration => '이 Golem 빌드의 구성이 잘못되어 시작할 수 없습니다.';

  @override
  String get launchUnknownFailure => 'Golem이 시작을 완료할 수 없습니다.';

  @override
  String get tryAgain => '다시 시도';

  @override
  String get back => '뒤로';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get delete => '삭제';

  @override
  String get download => '다운로드';

  @override
  String get pause => '일시 정지';

  @override
  String get resume => '계속';

  @override
  String get retry => '다시 시도';

  @override
  String get reset => '재설정';

  @override
  String get done => '완료';

  @override
  String get settingsTitle => '설정';

  @override
  String get chatTitle => '대화';

  @override
  String get settingsSectionModel => '모델';

  @override
  String get settingsSectionApp => '앱';

  @override
  String get settingsSectionAbout => '정보';

  @override
  String get settingsModel => '모델';

  @override
  String get settingsResponseStyle => '응답 스타일';

  @override
  String get settingsSystemPrompt => '시스템 프롬프트';

  @override
  String get settingsAppearance => '화면 모양';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsPrivacyData => '개인정보 보호 및 데이터';

  @override
  String get settingsStorage => '저장 공간';

  @override
  String get settingsBenchmark => '벤치마크';

  @override
  String get settingsModelAttribution => '모델 저작자 표시';

  @override
  String get settingsOpenSourceLicenses => '오픈 소스 라이선스';

  @override
  String get settingsAboutGolem => 'Golem 정보';

  @override
  String get languageSystem => '시스템 기본값';

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
  String get languageSystemDetail => '이 기기에서 선택한 언어를 사용합니다.';

  @override
  String get languageSaveFailed => '언어를 저장할 수 없습니다. 이전 선택으로 복원했습니다.';

  @override
  String get preferencesLoadFailed => '환경설정을 불러올 수 없습니다.';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get showInferenceMetrics => '추론 측정값 표시';

  @override
  String get alwaysExpandReasoning => '항상 추론 펼치기';

  @override
  String get hapticsOnSend => '전송 시 햅틱 피드백';

  @override
  String get textSize => '텍스트 크기';

  @override
  String get newChat => '새 대화';

  @override
  String get searchChats => '대화 검색';

  @override
  String get settings => '설정';

  @override
  String get rename => '이름 변경';

  @override
  String get renameChat => '대화 이름 변경';

  @override
  String get shareTranscript => '대화 내용 공유';

  @override
  String get pinToTop => '상단에 고정';

  @override
  String get unpin => '고정 해제';

  @override
  String get deleteChatTitle => '대화를 삭제할까요?';

  @override
  String get deleteChatMessage => '이 대화가 기기에서 삭제됩니다.';

  @override
  String get today => '오늘';

  @override
  String get yesterday => '어제';

  @override
  String get previousSevenDays => '지난 7일';

  @override
  String get older => '이전';

  @override
  String get noChatsYet => '아직 대화가 없습니다';

  @override
  String get noSearchResults => '대화를 찾을 수 없습니다';

  @override
  String get jumpToLatest => '최신 메시지로 이동';

  @override
  String get messagePlaceholder => 'Golem에게 메시지 보내기';

  @override
  String get sendMessage => '메시지 보내기';

  @override
  String get stopGenerating => '생성 중지';

  @override
  String get attach => '첨부';

  @override
  String get copy => '복사';

  @override
  String get copied => '복사됨';

  @override
  String get reasoning => '추론';

  @override
  String get showReasoning => '추론 표시';

  @override
  String get hideReasoning => '추론 숨기기';

  @override
  String get thinking => '생각하는 중…';

  @override
  String get model => '모델';

  @override
  String get models => '모델';

  @override
  String get allModels => '전체';

  @override
  String get installedModels => '설치됨';

  @override
  String get recommended => '추천';

  @override
  String get activeModel => '활성 모델';

  @override
  String get state => '상태';

  @override
  String get revision => '리비전';

  @override
  String get quantization => '양자화';

  @override
  String get size => '크기';

  @override
  String get promptProfile => '프롬프트 프로필';

  @override
  String get repository => '저장소';

  @override
  String get context => '컨텍스트';

  @override
  String get input => '입력';

  @override
  String get textOnly => '텍스트';

  @override
  String get textAndImages => '텍스트 + 이미지';

  @override
  String get downloadProgress => '다운로드 진행률';

  @override
  String get verifyingFiles => '파일 확인 중…';

  @override
  String get keep => '유지';

  @override
  String deleteModelTitle(String modelName) {
    return '$modelName을(를) 삭제할까요?';
  }

  @override
  String get deleteModelMessage => '다운로드한 파일이 기기에서 삭제됩니다. 나중에 다시 다운로드할 수 있습니다.';

  @override
  String downloadSize(String size) {
    return '다운로드 · $size';
  }

  @override
  String bytesDecimal(String value) {
    return '${value}GB';
  }

  @override
  String chatCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '대화 $count개',
      one: '대화 1개',
      zero: '대화 없음',
    );
    return '$_temp0';
  }

  @override
  String get defaultValue => '기본값';

  @override
  String get customValue => '사용자 지정';

  @override
  String get stylePrecise => '정확하게';

  @override
  String get styleBalanced => '균형 있게';

  @override
  String get styleCreative => '창의적으로';

  @override
  String get advancedMode => '고급 모드';

  @override
  String get advancedModeDetail =>
      '샘플링 설정, 사용자 지정 시스템 프롬프트 및 Hugging Face 저장소 직접 불러오기.';

  @override
  String get aboutLegal => '정보 및 법적 고지';

  @override
  String get openSourcePrivacyFootnote =>
      'Golem은 오픈 소스입니다. 이 화면의 어떤 정보도 외부로 전송되지 않습니다.';

  @override
  String get simulatedInferenceBanner => '시뮬레이션 추론 · 하드웨어 검증 안 됨';

  @override
  String get theme => '테마';

  @override
  String get inTranscript => '대화 내용에서';

  @override
  String get textPreview => '이 정도면 적당합니다.';

  @override
  String percentValue(int value) {
    return '$value퍼센트';
  }

  @override
  String languageSelected(String language) {
    return '$language 선택됨';
  }

  @override
  String get modelDownloadsSimulated =>
      '모델 다운로드는 고정된 카탈로그의 결정론적 시뮬레이션이며 네트워크에 접근하지 않습니다.';

  @override
  String get modelDownloadsReal =>
      '모델 다운로드는 HTTPS를 통해 Hugging Face에서 고정된 아티팩트를 가져옵니다.';

  @override
  String get inferenceSimulated =>
      '추론은 결정론적 UI 시뮬레이션이며 모델 가중치, 엔진 또는 하드웨어 측정을 포함하지 않습니다.';

  @override
  String get inferenceLocal => '추론은 활성 모델과 함께 이 기기의 로컬 엔진에서 실행됩니다.';

  @override
  String get networkPrivacyStatement =>
      '그 밖의 어떤 기능도 네트워크에 접근하지 않으며 Golem은 다른 앱의 데이터를 읽지 않습니다.';

  @override
  String get saveFailed => '저장할 수 없습니다. 다시 시도하세요.';

  @override
  String get firstRunTagline => '외부 서버에 연락하지 않는 대화 앱.';

  @override
  String get firstRunIntroduction =>
      'Golem은 오픈 모델 하나를 휴대전화에 불러와 그곳에서 실행합니다. 계정도, 서버도, 다른 곳에 저장되는 대화 사본도 없습니다.';

  @override
  String get promisePrivateTitle => '기기 밖으로 나가지 않습니다';

  @override
  String get promisePrivateDetail => '메시지는 Golem의 비공개 저장 공간에 보관됩니다.';

  @override
  String get promiseOfflineTitle => '연결 없이 작동합니다';

  @override
  String get promiseOfflineDetail => '모델을 한 번 다운로드하면 끝입니다.';

  @override
  String get promiseControlTitle => '원한다면 모든 설정을 직접';

  @override
  String get promiseControlDetail => '응답 스타일, 시스템 프롬프트 및 샘플링 설정.';

  @override
  String get getStarted => '시작하기';

  @override
  String get oneModelHeadline => '모델 하나. 설정할 것은 없습니다.';

  @override
  String get noCompatibleModel => '이 빌드에서 호환되는 모델을 찾을 수 없습니다.';

  @override
  String modelOfflineIntroduction(String modelName) {
    return 'Golem은 $modelName을(를) 한 번 다운로드한 뒤 네트워크 없이 대화에 답합니다.';
  }

  @override
  String get downloadUnavailable => '다운로드할 수 없음';

  @override
  String get chooseDifferentModel => '다른 모델 선택';

  @override
  String tokensThousands(int count) {
    return '토큰 $count천 개';
  }

  @override
  String get featuredModelDetail =>
      '일상적인 글쓰기, 요약 및 간단한 코드에 적합합니다. 모델 속도는 이 휴대전화에 따라 달라지며 실행 전에는 예측하지 않습니다.';

  @override
  String get allModelsTitle => '모든 모델';

  @override
  String get catalogSimulationDetail =>
      '이 QA 빌드는 고정된 전체 카탈로그를 표시합니다. 다운로드와 모델 실행은 시뮬레이션됩니다.';

  @override
  String get catalogDeviceDetail =>
      '이 빌드의 엔진용 모델을 선택할 수 있습니다. 더 큰 모델에는 권장 기기 등급이 필요합니다.';

  @override
  String get chooseModel => '모델 선택';

  @override
  String get startChatting => '대화 시작';

  @override
  String get pauseDownload => '다운로드 일시 정지';

  @override
  String get retryDownload => '다운로드 다시 시도';

  @override
  String get resumeDownload => '다운로드 계속';

  @override
  String modelReady(String modelName) {
    return '$modelName 준비됨';
  }

  @override
  String modelVerifying(String modelName) {
    return '$modelName 확인 중';
  }

  @override
  String modelDownloading(String modelName) {
    return '$modelName 다운로드 중';
  }

  @override
  String get selectedCatalogUnavailable => '선택한 카탈로그 항목을 사용할 수 없습니다.';

  @override
  String get downloadFailed => '다운로드에 실패했습니다. 다시 시도할 수 있습니다.';

  @override
  String downloadInsufficientStorage(String required, String available) {
    return '모델에 $required의 여유 공간이 필요하지만 $available만 사용할 수 있습니다.';
  }

  @override
  String downloadHashVerificationFailed(String fileName) {
    return '$fileName의 무결성 확인에 실패했습니다. 다시 다운로드하세요.';
  }

  @override
  String downloadUnexpectedFileSize(String fileName) {
    return '$fileName의 크기가 올바르지 않습니다. 다시 다운로드하세요.';
  }

  @override
  String get downloadSimulationComplete =>
      '결정론적 QA 시뮬레이션이 완료되었으며 가중치는 저장되지 않았습니다.';

  @override
  String get downloadComplete =>
      '이 기기에서 확인되었습니다. 이제 Golem은 네트워크 연결 없이 답할 수 있습니다.';

  @override
  String downloadAmount(String downloaded, String total) {
    return '$total 중 $downloaded';
  }

  @override
  String get downloadNoteTitle => '최고 속도를 위해 Golem을 열어 두세요.';

  @override
  String downloadNoteBody(
    String platform,
    String rate,
    String backgroundDuration,
    String foregroundDuration,
  ) {
    return '나가도 괜찮습니다. $platform에서는 백그라운드 다운로드 속도가 약 $rate로 제한되어, $foregroundDuration 대신 $backgroundDuration 정도 걸립니다.';
  }

  @override
  String aboutMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count분',
    );
    return '$_temp0';
  }

  @override
  String etaAboutMinutesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '약 $count분 남음',
    );
    return '$_temp0';
  }

  @override
  String amountLeft(String amount) {
    return '$amount 남음';
  }

  @override
  String stoppedAtPercent(int percent) {
    return '$percent%에서 중단됨';
  }

  @override
  String rateMbs(String rate) {
    return '$rate MB/s';
  }

  @override
  String get paused => '일시 중지됨';

  @override
  String get gettingGolemReady => 'Golem 준비 중';

  @override
  String get oneDownloadPitch => '지금 한 번만 다운로드하면 Golem이 이 기기에서만 답합니다.';

  @override
  String downloadedAmount(String amount) {
    return '다운로드됨 · $amount';
  }

  @override
  String get privacyFootnote => '모델은 이 기기에 저장됩니다. 입력한 내용은 업로드되지 않습니다.';

  @override
  String get dismissNote => '닫기';

  @override
  String get chatsStayAvailable => '대화는 계속 사용할 수 있습니다.';

  @override
  String get modelsUnavailableGeneric => '이 기기에서는 Golem이 모델을 실행할 수 없습니다.';

  @override
  String get unsupportedFeaturesRemain =>
      '모델을 다운로드하지 않습니다. 대화, 기록, 설정 및 내보내기는 계속 사용할 수 있습니다.';

  @override
  String get continueToGolem => 'Golem으로 계속';

  @override
  String get modelChoiceSaveFailed => '모델 선택을 저장할 수 없습니다. 다시 시도하세요.';

  @override
  String get setupSaveFailed => 'Golem이 설정을 저장할 수 없습니다. 다시 시도하세요.';

  @override
  String get simulateDownloadTitle => '이 다운로드를 시뮬레이션할까요?';

  @override
  String get downloadModelTitle => '이 모델을 다운로드할까요?';

  @override
  String simulateDownloadMessage(String modelName, String size) {
    return '$modelName은(는) $size 다운로드로 표시됩니다. 이 QA 시뮬레이션은 네트워크를 사용하거나 모델 가중치를 저장하지 않습니다.';
  }

  @override
  String downloadModelMessage(String modelName, String size) {
    return '$modelName은(는) Hugging Face에서 $size를 다운로드합니다. 해당 공간 외에 500MiB를 더 확보하세요. Wi-Fi를 권장하며 모바일 데이터 요금이 발생할 수 있습니다.';
  }

  @override
  String get notNow => '나중에';

  @override
  String get simulate => '시뮬레이션';

  @override
  String finishModelSetup(String modelName) {
    return '$modelName 설정 완료';
  }

  @override
  String modelDownloadPaused(String modelName) {
    return '$modelName 다운로드 일시 정지됨';
  }

  @override
  String modelNeedsAttention(String modelName) {
    return '$modelName을(를) 확인해야 합니다';
  }

  @override
  String get setupDownloadPrompt => 'Golem을 사용하기 전에 선택한 모델을 다운로드하고 검증하세요.';

  @override
  String get qaDownloadShort => '결정론적 QA 시뮬레이션. 네트워크 및 가중치 없음.';

  @override
  String get downloadBeforeSending => '메시지를 보내려면 모델 다운로드와 확인이 완료되어야 합니다.';

  @override
  String get resumeProgressKept => '준비되면 계속하세요. 기존 진행 상황은 유지됩니다.';

  @override
  String get checkingDownloadedFiles => '실행하기 전에 다운로드한 파일을 확인하고 있습니다.';

  @override
  String get downloadFailedChatsSafe => '다운로드에 실패했습니다. 대화에는 영향이 없습니다.';

  @override
  String get ready => '준비됨.';

  @override
  String get conversationsAppearHere => '대화가 여기에 표시됩니다.';

  @override
  String get pinned => '고정됨';

  @override
  String get unpinned => '고정 해제됨';

  @override
  String get earlier => '이전';

  @override
  String get conversationActions => '대화 작업';

  @override
  String deleteNamedChatMessage(String title) {
    return '“$title” 및 모든 메시지가 이 기기에서 삭제됩니다.';
  }

  @override
  String get chatDeleted => '대화 삭제됨';

  @override
  String storageAmount(String used, String total) {
    return '$total 중 $used';
  }

  @override
  String get closeConversations => '대화 목록 닫기';

  @override
  String get discard => '버리기';

  @override
  String downloadNamedModel(String modelName, String size) {
    return '$modelName 다운로드($size)';
  }

  @override
  String get addToChat => '이 대화에 추가';

  @override
  String get photoLibrary => '사진 보관함';

  @override
  String get takePhoto => '사진 촬영';

  @override
  String get files => '파일';

  @override
  String imagesPrivateDetail(String modelName) {
    return '이미지는 이 기기에서 읽습니다. $modelName은(는) 이미지를 볼 수 있으며 업로드되는 것은 없습니다.';
  }

  @override
  String imagesUnsupportedDetail(String modelName) {
    return '$modelName은(는) 텍스트만 처리합니다. 이미지를 첨부하려면 이미지를 읽는 모델로 전환하세요.';
  }

  @override
  String get unsupportedImageType =>
      '지원되지 않는 파일 형식입니다. JPEG, PNG 또는 WebP 이미지를 사용하세요.';

  @override
  String get imageTooLarge => '이 이미지는 첨부하기에 너무 큽니다.';

  @override
  String get imageUnreadable => '이 이미지를 읽을 수 없습니다.';

  @override
  String get imagePermissionDenied =>
      '사진을 첨부하려면 Golem에 카메라 및 사진 접근 권한이 필요합니다. 설정에서 권한을 켜세요.';

  @override
  String get imageAddFailed => '이 사진을 추가할 수 없습니다.';

  @override
  String get removeAttachedImage => '첨부 이미지 제거';

  @override
  String get modelForChat => '이 대화의 모델';

  @override
  String get reasoningOn => '추론 켜짐';

  @override
  String get reasoningOff => '추론 꺼짐';

  @override
  String get think => '생각하기';

  @override
  String get startPrivateConversation => '비공개 대화 시작';

  @override
  String get whatAreWeBuilding => '무엇을 만들어 볼까요?';

  @override
  String get cannotRunModelsHere => '여기서는 Golem이 모델을 실행할 수 없습니다';

  @override
  String simulatedModelPrivacy(String modelName) {
    return '이 미리보기는 휴대전화에서 $modelName을(를) 시뮬레이션합니다. 여기에 입력한 내용은 외부로 전송되지 않습니다.';
  }

  @override
  String localModelPrivacy(String modelName) {
    return '$modelName이(가) 이 휴대전화에서 불러와져 실행 중입니다. 여기에 입력한 내용은 외부로 전송되지 않습니다.';
  }

  @override
  String downloadedModelPrivacy(String modelName) {
    return '$modelName이(가) 이 휴대전화에 다운로드되어 검증되었습니다. 메시지를 보내면 불러옵니다. 여기에 입력한 내용은 외부로 전송되지 않습니다.';
  }

  @override
  String validatedModelPrivacy(String modelName) {
    return '$modelName이(가) 이 세션용으로 검증되었으며 이 휴대전화에서만 실행됩니다. 여기에 입력한 내용은 외부로 전송되지 않습니다.';
  }

  @override
  String get starterDraftReply => '답장 초안 작성';

  @override
  String get starterDraftReplyPrompt => '이 메시지에 대한 답장 초안을 작성하세요: ';

  @override
  String get starterExplain => '내용 설명';

  @override
  String get starterExplainPrompt => '간단히 설명하세요: ';

  @override
  String get starterRewrite => '내 글 다시 쓰기';

  @override
  String get starterRewritePrompt => '명확하게 읽히도록 다시 작성하세요: ';

  @override
  String get starterSummarise => '메모 요약';

  @override
  String get starterSummarisePrompt => '이 메모를 요약하세요: ';

  @override
  String get noChatsMatchSearch => '검색과 일치하는 대화가 없습니다.';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '대화 $count개',
      one: '대화 1개',
    );
    return '$_temp0';
  }

  @override
  String get localSearchPrivacy => '검색은 로컬 데이터베이스에서 실행됩니다. 인덱스는 업로드되지 않습니다.';

  @override
  String searchMatchSummary(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '일치 항목 $count개',
      one: '일치 항목 1개',
    );
    return '$date · $_temp0';
  }

  @override
  String stoppedAfterTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '토큰 $count개',
      one: '토큰 1개',
    );
    return '$_temp0 후 중지됨';
  }

  @override
  String get copyMessage => '메시지 복사';

  @override
  String get regenerateResponse => '응답 다시 생성';

  @override
  String get shareMessage => '메시지 공유';

  @override
  String get messageActions => '메시지 작업';

  @override
  String get regenerate => '다시 생성';

  @override
  String get branchFromHere => '여기서 분기';

  @override
  String get share => '공유';

  @override
  String get deleteMessage => '메시지 삭제';

  @override
  String get copiedToClipboard => '클립보드에 복사됨';

  @override
  String get newBranchStarted => '새 분기 시작됨';

  @override
  String get yourMessage => '내 메시지';

  @override
  String get golemResponse => 'Golem 응답';

  @override
  String get editAndRetry => '수정 후 다시 시도';

  @override
  String get editMessage => '메시지 수정';

  @override
  String get userSpeaker => '나';

  @override
  String get assistantSpeaker => 'Golem';

  @override
  String get saveAndRegenerate => '저장 후 다시 생성';

  @override
  String get generationFailed => '응답을 생성하는 중 문제가 발생했습니다.';

  @override
  String get attachmentUnavailableFailure =>
      '이 대화의 이미지를 더 이상 사용할 수 없습니다. 이 메시지를 삭제하고 다시 보내세요.';

  @override
  String get modelUnavailableFailure =>
      '이 대화의 모델을 현재 Golem 버전에서 사용할 수 없습니다. 계속하려면 다른 모델을 선택하세요.';

  @override
  String get unsupportedModelFailure =>
      'Golem이 이 모델의 대화 템플릿 또는 파일을 사용할 수 없습니다. 계속하려면 지원되는 모델을 선택하세요.';

  @override
  String get unsupportedImagesFailure =>
      '이 모델은 메시지의 이미지를 읽을 수 없습니다. 메시지를 삭제하거나 이미지를 읽는 모델을 선택하세요.';

  @override
  String get invalidModelArtifactFailure =>
      '설치된 모델이 없거나 손상되었거나 현재 Golem 버전과 호환되지 않습니다. 다른 모델을 선택하거나 다시 다운로드하세요.';

  @override
  String get attachmentSaveFailed => '이미지를 저장할 수 없습니다. 다시 첨부해 보세요.';

  @override
  String modelMissingForChat(String modelName) {
    return '$modelName이(가) 아직 이 기기에 다운로드되지 않았습니다. 이 대화에서 사용하려면 다운로드하세요.';
  }

  @override
  String get contextExhausted =>
      '이 대화는 모델의 컨텍스트 창에 비해 너무 깁니다. 계속하려면 새 대화를 시작하세요.';

  @override
  String get outOfMemory => '응답 생성 중 모델의 메모리가 부족해졌습니다. 다른 앱을 닫고 다시 시도하세요.';

  @override
  String get insufficientMemory =>
      '이 모델을 불러올 여유 메모리가 부족합니다. 다른 앱을 닫거나 더 작은 모델을 선택하세요.';

  @override
  String get budgetExhausted =>
      '모델이 답변을 만들기 전에 토큰 예산을 모두 사용했습니다. 다시 시도하거나 응답 설정을 조정하세요.';

  @override
  String imageCountSentence(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' 이미지 $count개.',
      one: ' 이미지 1개.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String tokenRateSummary(String rate, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '토큰 $count개',
      one: '토큰 1개',
    );
    return '$rate tok/s · $_temp0';
  }

  @override
  String get aiDisclaimer => 'AI 응답은 부정확할 수 있습니다. 중요한 정보를 확인하세요.';

  @override
  String get privacyStatement =>
      'Golem은 계정을 만들지 않고 분석 데이터를 보내지 않으며 모델 다운로드 후 네트워크 권한을 제거합니다. 거부할 항목이 없습니다.';

  @override
  String get onThisPhone => '이 휴대전화에서';

  @override
  String get saveChatHistory => '대화 기록 저장';

  @override
  String get saveHistoryOffDetail => '끄면 앱을 닫을 때 모든 대화가 사라집니다.';

  @override
  String get yourData => '내 데이터';

  @override
  String get exportAllChats => '모든 대화 내보내기';

  @override
  String get deleteAllChats => '모든 대화 삭제';

  @override
  String get stopSavingChatsTitle => '대화 저장을 중지할까요?';

  @override
  String get stopSavingChatsMessage =>
      '이 기기에 이미 저장된 대화는 지금 삭제됩니다. 열린 대화는 앱을 닫을 때까지 유지되며 디스크에 새로 기록되지 않습니다.';

  @override
  String get keepSaving => '계속 저장';

  @override
  String get stopAndDelete => '중지하고 삭제';

  @override
  String get deleteSavedChatsFailed => '저장된 대화를 삭제할 수 없습니다. 다시 시도하세요.';

  @override
  String get chatsExportSubject => 'Golem 대화 내보내기';

  @override
  String get deleteAllChatsTitle => '모든 대화를 삭제할까요?';

  @override
  String get deleteAllChatsMessage => '모든 대화가 이 기기에서 삭제됩니다. 다운로드한 모델은 유지됩니다.';

  @override
  String get chatsDeleted => '대화 삭제됨';

  @override
  String get deleteChatsFailed => '대화를 삭제할 수 없습니다. 다시 시도하세요.';

  @override
  String get systemPromptDetail =>
      '각 새 응답 전에 대화보다 먼저 전송되는 고정 지침입니다. 모델의 기본 동작을 유지하려면 비워 두세요.';

  @override
  String get systemPromptExample => '예: 간결하고 쉬운 말로 답하세요.';

  @override
  String get resetToDefault => '기본값으로 재설정';

  @override
  String get systemPromptLocalFootnote => '프롬프트는 두 모델 모두에 적용되며 이 기기에 보관됩니다.';

  @override
  String get storageReadFailed => '저장 공간을 읽을 수 없습니다.';

  @override
  String get downloadedModels => '다운로드한 모델';

  @override
  String get clearInferenceCache => '추론 캐시 지우기';

  @override
  String get modelDeletionFootnote => '모델을 삭제하면 즉시 공간이 확보됩니다. 대화는 유지됩니다.';

  @override
  String get cacheCleared => '캐시 지워짐';

  @override
  String storageFree(String size) {
    return '$size 여유';
  }

  @override
  String storageModelsAmount(String size) {
    return '모델 $size';
  }

  @override
  String storageChatsAmount(String size) {
    return '대화 $size';
  }

  @override
  String storageImagesAmount(String size) {
    return '이미지 $size';
  }

  @override
  String storageCacheAmount(String size) {
    return '캐시 $size';
  }

  @override
  String get noDownloadedModels => '아직 다운로드한 모델이 없습니다.';

  @override
  String get active => '활성';

  @override
  String get partial => '일부';

  @override
  String deleteModelArtifactTitle(String modelName, String format) {
    return '$modelName · $format을(를) 삭제할까요?';
  }

  @override
  String deleteModelStorageMessage(String size) {
    return '이 기기에서 $size를 제거합니다. 나중에 모델을 다시 다운로드할 수 있습니다.';
  }

  @override
  String megabytes(int value) {
    return '${value}MB';
  }

  @override
  String get licensesIntroduction =>
      'Golem은 오픈 소스 소프트웨어로 제작되었습니다. 이 고지는 오프라인에서 볼 수 있으며 이 빌드가 사용하는 Dart, 네이티브 엔진 및 모델 라이선스를 포함합니다.';

  @override
  String licenseEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '라이선스 항목 $count개',
      one: '라이선스 항목 1개',
    );
    return '$_temp0';
  }

  @override
  String get licensesLoadFailed => '라이선스를 불러올 수 없습니다.';

  @override
  String get licensesRetryDetail => '번들 파일은 이 기기에 그대로 있습니다. 다시 불러오세요.';

  @override
  String showLicenseFor(String name) {
    return '$name 라이선스 표시';
  }

  @override
  String hideLicenseFor(String name) {
    return '$name 라이선스 숨기기';
  }

  @override
  String get modelAttributionIntroduction =>
      'Golem에는 모델 가중치가 포함되지 않습니다. 다운로드를 승인한 후 여기에 표시된 정확한 아티팩트만 다운로드합니다.';

  @override
  String get officialModelCard => '공식 모델 카드';

  @override
  String get license => '라이선스';

  @override
  String get customRepositoryTerms =>
      '직접 추가한 저장소에는 해당 원본의 약관이 적용됩니다. Golem은 이를 인증하거나 재배포하지 않습니다.';

  @override
  String get startupFailed => '시작 실패';

  @override
  String get startupCouldNotFinish => 'Golem이 시작을 완료할 수 없음';

  @override
  String get preparingFirstRun => '첫 실행 준비 중';

  @override
  String get preparingSetup => '설정 준비 중';

  @override
  String get startingOnDevice => '이 기기에서 Golem 시작 중';

  @override
  String get gettingReady => '준비 중';

  @override
  String get splashTagline => '비공개, 로컬, 언제나 준비됨.';

  @override
  String get chatHistoryNotSaving =>
      '대화 기록이 저장되지 않습니다. 앱을 닫으면 최신 변경 사항이 손실될 수 있습니다.';

  @override
  String get saving => '저장 중…';

  @override
  String get reasoningLive => '실시간 추론';

  @override
  String get expanded => '펼쳐짐';

  @override
  String get collapsed => '접힘';

  @override
  String get reasoningLiveBadge => '추론 · 실시간';

  @override
  String generatingAtRate(String rate) {
    return '생성 중 · $rate tok/s';
  }

  @override
  String get imageUnavailable => '이미지를 더 이상 사용할 수 없음';

  @override
  String get loadingImage => '이미지 불러오는 중';

  @override
  String get golemResponding => 'Golem이 응답하는 중';

  @override
  String get responseFinished => '응답 완료';

  @override
  String get chatHistoryLoadFailed => '대화 기록을 불러올 수 없습니다.';

  @override
  String get openConversations => '대화 목록 열기';

  @override
  String get images => '이미지';

  @override
  String get stop => '중지';

  @override
  String get send => '보내기';

  @override
  String get copyCode => '코드 복사';

  @override
  String get code => '코드';

  @override
  String get unsupportedDevice => '지원되지 않는 기기';

  @override
  String get simulated => '시뮬레이션';

  @override
  String get onDevice => '기기 내';

  @override
  String get responseStyle => '응답 스타일';

  @override
  String responseStyleDescription(String modelName) {
    return '$modelName이(가) 자유롭게 답할 수 있는 정도입니다. 새 응답에만 적용됩니다.';
  }

  @override
  String get advancedSamplingHint =>
      '온도, top-p 및 토큰 예산을 직접 설정하려면 설정에서 고급 모드를 켜세요.';

  @override
  String get sampling => '샘플링';

  @override
  String get stylePreciseDetail => '사실에 충실합니다. 코드와 요약에 적합합니다.';

  @override
  String get styleBalancedDetail => '모델 자체 기본값입니다. 권장됩니다.';

  @override
  String get styleCreativeDetail => '더 자유롭고 다양하지만 가끔 틀릴 수 있습니다.';

  @override
  String selectedOption(String name) {
    return '$name 선택됨';
  }

  @override
  String get noTunableProfile => '이 빌드에는 이 모델의 조정 가능한 프로필이 없습니다.';

  @override
  String get settingsLoadFailed => '설정을 불러올 수 없습니다.';

  @override
  String get samplingTemperature => '온도';

  @override
  String get samplingTopP => 'Top-p';

  @override
  String get samplingTopK => 'Top-k';

  @override
  String get off => '끔';

  @override
  String get maxTokens => '최대 토큰';

  @override
  String get contextLength => '컨텍스트 길이';

  @override
  String styleSource(String style) {
    return '· $style';
  }

  @override
  String get defaultSource => '· 기본값';

  @override
  String get tokenBudgetFootnote => '토큰 예산은 프롬프트를 위해 항상 컨텍스트 토큰 512개를 남겨 둡니다.';

  @override
  String get pinnedTokenBudgetFootnote =>
      '토큰 예산은 프롬프트를 위해 항상 컨텍스트 토큰 512개를 남겨 둡니다. 생각 모드는 이 모델의 고정 샘플링을 유지하며 예산은 두 모드 모두에 적용됩니다.';

  @override
  String get modelsLoadFailed => '모델 상태를 불러올 수 없습니다.';

  @override
  String get modelRuntimeFailed => '모델 런타임이 예기치 않게 중지되었습니다. 다시 불러오세요.';

  @override
  String get nothingInstalled => '아직 설치된 항목이 없습니다.';

  @override
  String get nothingInstalledSimulated =>
      '아직 설치된 항목이 없습니다. 여기의 다운로드는 결정론적 시뮬레이션입니다.';

  @override
  String get runtime => '런타임';

  @override
  String get customRepository => '사용자 지정 저장소';

  @override
  String get none => '없음';

  @override
  String get noneSimulatedInference => '없음 · 시뮬레이션 추론';

  @override
  String get unloadRuntime => '런타임 언로드';

  @override
  String get loadRuntime => '런타임 로드';

  @override
  String get unloadSimulatedRuntime => '시뮬레이션 런타임 언로드';

  @override
  String get loadSimulatedRuntime => '시뮬레이션 런타임 로드';

  @override
  String get modelSaveFailed => '모델을 저장할 수 없습니다. 다시 시도하세요.';

  @override
  String get modelAdded => '모델 추가됨';

  @override
  String get repositoryMalformedIdentifier =>
      'unsloth/gemma-4-E2B-it-qat-GGUF와 같이 소유자/이름 형식의 공개 저장소를 입력하세요.';

  @override
  String get repositoryNotFoundOrPrivate =>
      '저장소를 읽을 수 없습니다. 이름을 확인하세요. 비공개 저장소는 지원되지 않습니다.';

  @override
  String get repositoryGated =>
      '이 저장소는 Hugging Face에서 라이선스 수락이 필요합니다. 접근 제한 저장소는 지원되지 않습니다.';

  @override
  String get repositoryDisabled => '이 저장소는 Hugging Face에서 비활성화되었습니다.';

  @override
  String get repositoryRateLimited =>
      'Hugging Face가 이 기기의 요청을 제한하고 있습니다. 잠시 후 다시 시도하세요.';

  @override
  String get repositoryNetwork =>
      'Hugging Face에 연결할 수 없습니다. 연결을 확인하고 다시 시도하세요.';

  @override
  String get repositoryMalformedMetadata =>
      'Hugging Face가 이 저장소에 대해 예상치 못한 데이터를 반환했습니다. 잠시 후 다시 시도하세요.';

  @override
  String get repositoryUnsafePath => '이 저장소에는 앱이 쓰지 않을 파일 경로가 포함되어 있습니다.';

  @override
  String get repositoryNoWeights => '이 저장소에서 엔진이 불러올 수 있는 가중치를 찾지 못했습니다.';

  @override
  String get repositoryShardedWeights =>
      '이 모델은 여러 가중치 파일로 나뉘어 있어 아직 지원되지 않습니다. 단일 파일 버전을 선택하세요.';

  @override
  String get repositoryUnsafeWeightFormat =>
      '이 저장소는 앱이 불러오지 않는 형식으로 가중치를 제공합니다. safetensors와 GGUF만 지원됩니다.';

  @override
  String get repositoryMissingRequiredFile => '이 저장소에 엔진이 불러오는 데 필요한 파일이 없습니다.';

  @override
  String get repositoryInconsistentMetadata =>
      '저장소의 파일 목록이 일치하지 않아 안전하게 고정할 수 없습니다.';

  @override
  String get repositoryUnsupportedArchitecture =>
      '이 Golem 버전에서는 해당 모델 아키텍처를 실행할 수 없습니다.';

  @override
  String get repositoryHeaderTooLarge => '모델의 메타데이터가 앱에서 읽을 수 있는 크기보다 큽니다.';

  @override
  String get repositoryDuplicateEntry => '이미 추가된 저장소입니다.';

  @override
  String get repositoryRevisionPlaceholder => 'main — 또는 브랜치, 태그, 커밋';

  @override
  String get unknownTemplateWarning =>
      '다운로드하고 삭제할 수는 있지만 Golem이 프롬프트를 보낼 수 없습니다. 이 버전에서 대화 템플릿을 인식하지 못합니다.';

  @override
  String get simulatedRepositoryDetail =>
      '이 빌드는 다운로드를 시뮬레이션하므로 아래 리비전과 크기는 Hugging Face에서 읽지 않고 생성됩니다.';

  @override
  String get publicRepositoryDetail =>
      '공개 저장소만 지원됩니다. 확인 결과를 보기 전에는 아무것도 다운로드되지 않습니다.';

  @override
  String get readingRepository => '저장소 읽는 중…';

  @override
  String get chooseWeightFile => '이 저장소에는 여러 가중치 파일이 있습니다. 설치할 파일을 선택하세요:';

  @override
  String get notRecognized => '인식되지 않음';

  @override
  String moreFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 더 있음',
      one: '파일 1개 더 있음',
    );
    return '+ $_temp0';
  }

  @override
  String get addModel => '모델 추가';

  @override
  String get resolveRepository => '확인';

  @override
  String get activeBadge => '선택됨';

  @override
  String get loadedBadge => '불러옴';

  @override
  String modelStatusLabel(String modelName, String engine) {
    return '$modelName $engine 상태';
  }

  @override
  String downloadProgressLabel(String suffix) {
    return '다운로드$suffix';
  }

  @override
  String verifyingFilesStatus(String suffix) {
    return '파일 확인 중$suffix…';
  }

  @override
  String openRepository(String repository) {
    return 'Hugging Face에서 $repository 열기';
  }

  @override
  String modelSizeAndFiles(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개',
      one: '파일 1개',
    );
    return '$size · $_temp0';
  }

  @override
  String measuredSimulated(String rate) {
    return '$rate tok/s · 시뮬레이션';
  }

  @override
  String measuredOnPhone(String rate) {
    return '이 휴대전화에서 $rate tok/s';
  }

  @override
  String get measured => '측정됨';

  @override
  String downloadSizeAction(String size) {
    return '다운로드 · $size';
  }

  @override
  String get cancelAndDiscard => '취소하고 버리기';

  @override
  String get deleteDownload => '다운로드 삭제';

  @override
  String get notDownloaded => '다운로드 안 됨';

  @override
  String downloadingAmountStatus(
    String downloaded,
    String total,
    String suffix,
  ) {
    return '$total 중 $downloaded 다운로드 중$suffix';
  }

  @override
  String pausedAtStatus(String downloaded, String suffix) {
    return '$downloaded에서 일시 정지됨$suffix';
  }

  @override
  String verifyingStatus(String suffix) {
    return '확인 중$suffix';
  }

  @override
  String installedVerifiedStatus(String suffix) {
    return '설치 및 확인됨$suffix';
  }

  @override
  String get unloaded => '언로드됨';

  @override
  String get loading => '불러오는 중…';

  @override
  String get loadingSimulation => '시뮬레이션 불러오는 중…';

  @override
  String get readySimulated => '준비됨 · 시뮬레이션';

  @override
  String get stopped => '중지됨';

  @override
  String get benchmark => '벤치마크';

  @override
  String get protocol => '프로토콜';

  @override
  String get prompt => '프롬프트';

  @override
  String get run => '실행';

  @override
  String get warmup => '워밍업';

  @override
  String get maximumOutput => '최대 출력';

  @override
  String get seed => '시드';

  @override
  String get benchmarkProtocolDetail =>
      '추적되는 프로덕션 프롬프트 픽스처를 사용합니다. 출력과 시간은 결정론적 시뮬레이션일 뿐입니다.';

  @override
  String get simulationStatus => '시뮬레이션 상태';

  @override
  String get thermal => '열 상태';

  @override
  String get notMeasured => '측정 안 됨';

  @override
  String get lowPowerMode => '저전력 모드';

  @override
  String get notRead => '읽지 않음';

  @override
  String get hardwareValidation => '하드웨어 검증';

  @override
  String get no => '아니요';

  @override
  String get stopSimulatedBenchmark => '시뮬레이션 벤치마크 중지';

  @override
  String get runSimulatedBenchmark => '시뮬레이션 벤치마크 실행';

  @override
  String get generatingDeterministicResult => '결정론적 결과 생성 중…';

  @override
  String get simulatedResult => '시뮬레이션 결과';

  @override
  String get benchmarkPrompt => '벤치마크 프롬프트';

  @override
  String get shortExplanation => '짧은 설명';

  @override
  String get mediumReview => '중간 길이 검토';

  @override
  String get longSynthesis => '긴 종합';

  @override
  String get simulatedNotValidated => '시뮬레이션 · 하드웨어 검증 안 됨';

  @override
  String get generated => '생성됨';

  @override
  String tokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '토큰 $count개',
      one: '토큰 1개',
    );
    return '$_temp0';
  }

  @override
  String get decode => '디코드';

  @override
  String tokenRate(String rate) {
    return '$rate tok/s';
  }

  @override
  String get peakMemory => '최대 메모리';

  @override
  String get simulatedEndOfTurn => '시뮬레이션 턴 종료';

  @override
  String get benchmarkExportTitle => 'Golem 시뮬레이션 벤치마크';

  @override
  String get benchmarkExportText => '시뮬레이션 벤치마크 JSON — 하드웨어 검증 안 됨.';

  @override
  String get exportSimulatedJson => '시뮬레이션 JSON 내보내기';

  @override
  String get benchmarkSimulationNotice =>
      '이 화면은 흐름을 시뮬레이션합니다. 이 기기를 측정하지 않습니다.';

  @override
  String get deviceMissingInstructionSet =>
      '이 기기의 프로세서에 로컬 엔진에 필요한 명령어 집합이 없어 모델을 실행할 수 없습니다.';

  @override
  String get deviceBelowMemoryFloor =>
      '이 기기의 메모리가 Golem의 가장 작은 모델이 요구하는 수준보다 적어 다운로드가 꺼졌습니다. 대화와 설정에는 영향이 없습니다.';

  @override
  String outOfMemoryAtContext(int tokens) {
    final intl.NumberFormat tokensNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String tokensString = tokensNumberFormat.format(tokens);

    return '토큰 $tokensString개에서 메모리가 부족해졌습니다. 컨텍스트 길이를 줄이거나 더 작은 모델을 선택하세요.';
  }

  @override
  String get defaultLowercase => '기본값';

  @override
  String get stylePreciseLowercase => '정확하게';

  @override
  String get styleBalancedLowercase => '균형 있게';

  @override
  String get styleCreativeLowercase => '창의적으로';

  @override
  String hiddenEngineModels(int count, String engine) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '다른 엔진용 모델 $count개가 표시되지 않습니다.',
      one: '다른 엔진용 모델 1개가 표시되지 않습니다.',
    );
    return '$_temp0 이 빌드는 $engine을(를) 실행합니다.';
  }

  @override
  String get notAvailableOnDevice => '이 기기에서 사용할 수 없습니다.';

  @override
  String get pinnedByBuild => '이 빌드에 고정됨.';

  @override
  String otherEngineAdmission(String engine) {
    return '이 빌드는 $engine 엔진을 사용합니다.';
  }

  @override
  String get memoryUnreadableLighterModel =>
      'Golem이 휴대전화의 메모리를 읽을 수 없어 더 가벼운 모델을 제공합니다.';

  @override
  String get needsMoreReportedMemory => '이 휴대전화가 보고한 것보다 더 많은 메모리가 필요합니다.';

  @override
  String get modelsUnavailableOnDevice => '이 기기에서 모델을 사용할 수 없습니다.';

  @override
  String get unresolvedRepositoryReason =>
      '이 저장소는 Hugging Face에서 확인되지 않아 파일을 알 수 없습니다. 다시 추가하여 확인하세요.';

  @override
  String installedOtherEngine(String buildEngine, String modelEngine) {
    return '설치되었지만 이 빌드는 $buildEngine을(를) 실행하므로 $modelEngine 모델을 불러올 수 없습니다.';
  }

  @override
  String get unrecognizedChatTemplate =>
      '설치되었지만 Golem이 이 모델의 대화 템플릿을 인식하지 못해 프롬프트를 보낼 수 없습니다.';

  @override
  String get pickAfterDownload => '다운로드가 완료되면 선택하세요.';

  @override
  String get resumeForChat => '이 대화에서 사용하려면 다운로드를 계속하세요.';

  @override
  String get unfinishedDownload => '다운로드가 완료되지 않아 아직 선택할 수 없습니다.';

  @override
  String get downloadForChat => '이 대화에서 사용하려면 다운로드하세요.';

  @override
  String get customModelSummary => 'Hugging Face에서 직접 추가했습니다.';

  @override
  String get anotherModelDownloading => '다른 모델을 다운로드하고 있습니다.';

  @override
  String downloadingStatus(String suffix) {
    return '다운로드 중$suffix';
  }

  @override
  String verifyingFilesPicker(String suffix) {
    return '파일 확인 중$suffix';
  }

  @override
  String pausedDownloadAmount(String downloaded, String total, String suffix) {
    return '$total 중 $downloaded에서 일시 정지됨$suffix.';
  }

  @override
  String get readsPictures => '이미지 읽기 가능';

  @override
  String modelSpeedSimulated(String rate) {
    return '$rate tok/s 시뮬레이션';
  }

  @override
  String modelSpeedOnPhone(String rate) {
    return '이 휴대전화에서 $rate tok/s';
  }

  @override
  String get buildDefaultModel => '이 빌드의 기본 모델.';

  @override
  String get lighterModelUnknownMemory => '휴대전화의 메모리를 읽을 수 없어 선택된 더 가벼운 모델.';

  @override
  String get largerModelFits => '이 휴대전화에는 더 큰 모델을 위한 메모리가 있습니다.';

  @override
  String get sizedForPhone => '이 휴대전화의 메모리에 맞는 크기입니다.';

  @override
  String sideloadPreventsSwitch(String modelName) {
    return '이 빌드는 고정된 경로에서 $modelName을(를) 실행하므로 이 대화에서 모델을 바꿀 수 없습니다.';
  }

  @override
  String get modelLoadsNextMessage => '선택한 모델은 다음 메시지와 함께 불러옵니다.';

  @override
  String get selectedModel => '선택한 모델';

  @override
  String get manageModels => '모델 관리';

  @override
  String get gemmaModelSummary => '일상적인 글쓰기, 요약 및 간단한 코드에 적합한 균형 잡힌 범용 모델입니다.';

  @override
  String get qwenTwoBModelSummary =>
      '가장 작고 빠르게 답합니다. 짧은 질문과 여유 메모리가 적은 휴대전화에 적합합니다.';

  @override
  String get qwenFourBModelSummary => '코드와 수학에 강하며 답하기 전에 문제를 깊이 생각할 수 있습니다.';
}
