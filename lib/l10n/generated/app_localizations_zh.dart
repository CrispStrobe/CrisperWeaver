// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'CrisperWeaver';

  @override
  String get appTagline => '带说话人分离的音频转录';

  @override
  String get menuHistory => '历史记录';

  @override
  String get menuSettings => '设置';

  @override
  String get menuModels => '模型';

  @override
  String get menuSynthesize => '语音合成';

  @override
  String get menuTranslate => '文本翻译';

  @override
  String get menuLogs => '日志';

  @override
  String get menuAbout => '关于';

  @override
  String get menuOpenMore => '更多';

  @override
  String get tabInput => '输入';

  @override
  String get tabRun => '运行';

  @override
  String get tabOutput => '输出';

  @override
  String get navHome => '转录';

  @override
  String get engineReady => '引擎就绪';

  @override
  String get engineStarting => '引擎启动中…';

  @override
  String get audioInput => '音频输入';

  @override
  String get noFileSelected => '未选择文件';

  @override
  String get browse => '浏览';

  @override
  String get urlInputLabel => '或输入音频 URL';

  @override
  String get urlInputHint => 'https://example.com/audio.mp3';

  @override
  String get advancedOptions => '高级选项';

  @override
  String get language => '语言';

  @override
  String get languageAuto => '自动检测';

  @override
  String get model => '模型';

  @override
  String get transcribe => '转录';

  @override
  String get transcribing => '转录中…';

  @override
  String get stop => '停止';

  @override
  String get clear => '清空';

  @override
  String get transcriptionOutput => '转录结果';

  @override
  String get noTranscriptionYet => '暂无转录';

  @override
  String get noTranscriptionHint => '选择音频文件并开始转录';

  @override
  String get searchTranscription => '搜索转录内容…';

  @override
  String get noResultsFound => '未找到结果';

  @override
  String get noResultsHint => '请尝试其他搜索词';

  @override
  String get tabSegments => '片段';

  @override
  String get tabFullText => '全文';

  @override
  String get sharePlain => '分享纯文本';

  @override
  String get copyClipboard => '复制到剪贴板';

  @override
  String get saveAsTxt => '保存为 .txt';

  @override
  String get saveAsSrt => '保存为 .srt';

  @override
  String get saveAsVtt => '保存为 .vtt';

  @override
  String get saveAsJson => '保存为 .json';

  @override
  String get copied => '已复制';

  @override
  String get perfRtf => '实时率';

  @override
  String get perfAudio => '音频';

  @override
  String get perfWall => '实际时长';

  @override
  String get perfWords => '单词数';

  @override
  String get perfWps => '词/秒';

  @override
  String get perfEngine => '引擎';

  @override
  String get perfModel => '模型';

  @override
  String get perfFasterThanRealtime => '快于实时';

  @override
  String get perfSlowerThanRealtime => '慢于实时';

  @override
  String get diarizationTitle => '说话人分离';

  @override
  String get diarizationSubtitle => '识别录音中的不同说话人';

  @override
  String get diarizationEnableTooltip =>
      '为转写结果的每一段标注由谁说出（说话人 1、说话人 2……）。适合访谈和会议，会增加处理时间。';

  @override
  String get diarizationModel => '分离模型';

  @override
  String get diarizationModelHelper =>
      '选择运行哪种分离器。语音轮换检测无需额外模型；Pyannote 与 FoxNose 需要各自的 GGUF；立体声方法需要双声道音频。';

  @override
  String get minSpeakers => '最少说话人数';

  @override
  String get minSpeakersHelper => '说话人数量的下限。选择“自动”则由说话人分离自行估计。';

  @override
  String get maxSpeakers => '最多说话人数';

  @override
  String get maxSpeakersHelper => '说话人数量的上限。选择“自动”则由说话人分离自行估计。';

  @override
  String get diarizationSpeakerBoundsNote =>
      '只有 FoxNose 会直接使用这些上下限。其他方法中，上限仍会限制说话人重新聚类（需要说话人嵌入模型），下限可能被忽略。';

  @override
  String get auto => '自动';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppLanguage => '应用语言';

  @override
  String get settingsInterfaceLanguage => '界面语言';

  @override
  String get settingsSystemDefault => '跟随系统';

  @override
  String get settingsEngineSection => '转录引擎';

  @override
  String get settingsEnginePreferred => '首选引擎';

  @override
  String get settingsSelectEngine => '选择引擎';

  @override
  String settingsEngineSwitched(String engine) {
    return '已切换至 $engine';
  }

  @override
  String get settingsEngineSwitchFailed => '引擎切换失败';

  @override
  String settingsAudioQualityCurrent(int percent) {
    return '录音质量：$percent%';
  }

  @override
  String get settingsCacheCleared => '缓存已成功清除';

  @override
  String get settingsHfToken => 'HuggingFace API 令牌';

  @override
  String get settingsHfTokenNotSet => '未设置（访问门控模型时必填）';

  @override
  String get settingsModelsDir => '模型目录';

  @override
  String get settingsModelsDirDefault => '默认（应用沙箱内）';

  @override
  String get settingsModelsDirPickTitle => '选择模型目录';

  @override
  String get settingsModelsDirCurrentDefault =>
      '当前使用默认应用沙箱路径。选择自定义目录可与其他工具共享 GGUF 文件（例如外置硬盘）。';

  @override
  String settingsModelsDirCurrent(String path) {
    return '当前：$path';
  }

  @override
  String get settingsModelsDirPick => '选择…';

  @override
  String get settingsModelsDirReset => '使用默认';

  @override
  String settingsModelsDirSet(String path) {
    return '模型目录已设置为 $path';
  }

  @override
  String get languageEn => '英语';

  @override
  String get languageDe => '德语';

  @override
  String get languageEs => '西班牙语';

  @override
  String get languageFr => '法语';

  @override
  String get languageIt => '意大利语';

  @override
  String get languagePt => '葡萄牙语';

  @override
  String get languageZh => '中文';

  @override
  String get languageJa => '日语';

  @override
  String get languageKo => '韩语';

  @override
  String get languageRu => '俄语';

  @override
  String modelSize(String size) {
    return '大小：$size';
  }

  @override
  String modelDeleteConfirm(String name) {
    return '确定要删除 $name 吗？';
  }

  @override
  String get historyCopy => '复制';

  @override
  String get historyExportSrt => '导出 SRT';

  @override
  String get historyExportTxt => '导出 TXT';

  @override
  String get historyExportJson => '导出 JSON';

  @override
  String get historyDelete => '删除';

  @override
  String historyFailedToLoad(String error) {
    return '加载历史记录失败：$error';
  }

  @override
  String historySaved(String path) {
    return '已保存至 $path';
  }

  @override
  String historyExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get recorderDeleteTitle => '删除录音';

  @override
  String get recorderDeleteBody => '确定要删除此录音吗？';

  @override
  String get recorderQueuedForTranscription => '录音已加入转录队列。';

  @override
  String get recorderStream => '实时转录';

  @override
  String get recorderStreamTooltip => '实时麦克风转录（Whisper 滑动窗口），说话时即显示临时文本。';

  @override
  String get recorderSystemAudioTooltip =>
      '捕获系统音频（Zoom 会议、浏览器标签、播客应用）并实时转录。仅支持 macOS 13+；首次使用将提示授予屏幕录制权限。';

  @override
  String get recorderSystemAudioPermission =>
      '屏幕录制权限被拒绝。请前往系统设置 → 隐私与安全 → 屏幕录制，勾选 CrisperWeaver，然后重试。';

  @override
  String get recorderSystemAudioUnsupported =>
      '此平台暂不支持系统音频捕获。详见 PLAN.md §5.1.1。';

  @override
  String get outputShowTimestamps => '显示时间戳';

  @override
  String get outputShowSpeakers => '显示说话人';

  @override
  String get outputShowConfidence => '显示置信度';

  @override
  String get outputCopyAll => '全部复制';

  @override
  String get outputPlay => '播放';

  @override
  String get outputCopy => '复制';

  @override
  String get outputEdit => '编辑';

  @override
  String get outputPlaySegment => '播放片段';

  @override
  String get outputCopyText => '复制文本';

  @override
  String get outputEditSegment => '编辑片段';

  @override
  String get outputEditNotImplemented => '片段编辑功能尚未实现';

  @override
  String get outputEditAltSuggestions => '备选候选项';

  @override
  String get outputEditAltSuggestionsHint =>
      '点击单词可将其替换为 Whisper 在该步骤选出的备选项。使用高级选项中的备选候选数滑块。';

  @override
  String get outputEditAltPickTooltip => '为此单词选择备选候选项';

  @override
  String get outputRenameSpeakerTitle => '重命名说话人';

  @override
  String outputRenameSpeakerOriginal(String original) {
    return '原始标签：$original';
  }

  @override
  String get outputRenameSpeakerReset => '还原为原始标签';

  @override
  String get outputSegmentCopied => '片段已复制到剪贴板';

  @override
  String get outputAllCopied => '所有转录内容已复制到剪贴板';

  @override
  String outputPlayingSegment(String time) {
    return '正在播放片段：$time';
  }

  @override
  String get settingsLoading => '加载中…';

  @override
  String get transcribeLanguageLabel => '语言';

  @override
  String transcribeLoadingButton(String model) {
    return '正在加载 $model…';
  }

  @override
  String get transcribeLoadingFallback => '正在加载模型…';

  @override
  String transcribeLoadingDetail(String model) {
    return '正在加载模型：$model — 首次使用此模型约需 5–15 秒，Worker 池启动并将权重映射到内存。';
  }

  @override
  String transcribeStarting(String model) {
    return '开始下载：$model';
  }

  @override
  String transcribeUnsupportedFile(String name) {
    return '不支持的文件类型：$name';
  }

  @override
  String transcribeLoadedFile(String name) {
    return '已加载 $name';
  }

  @override
  String aboutEmail(String email) {
    return '电子邮件：$email';
  }

  @override
  String aboutPhone(String phone) {
    return '电话：$phone';
  }

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String get settingsTranscription => '转录';

  @override
  String get settingsDefaultModel => '默认模型';

  @override
  String get settingsDefaultLanguage => '默认语言';

  @override
  String get settingsAutoDetectLanguage => '自动检测语言';

  @override
  String get settingsAutoDetectLanguageSubtitle => '自动检测音频语言';

  @override
  String get settingsWordTimestamps => '词级时间戳';

  @override
  String get settingsWordTimestampsSubtitle => '为每个单词生成时间戳';

  @override
  String get settingsAudio => '音频';

  @override
  String get settingsAudioQuality => '音频质量';

  @override
  String get settingsKeepAudioFiles => '保留音频文件';

  @override
  String get settingsKeepAudioFilesSubtitle => '转录后保留已下载/录制的音频文件';

  @override
  String get settingsDiarization => '说话人分离';

  @override
  String get settingsEnableDiarizationByDefault => '默认启用';

  @override
  String get settingsEnableDiarizationByDefaultSubtitle => '为新转录任务自动启用说话人分离';

  @override
  String get settingsStorage => '存储';

  @override
  String get settingsClearCache => '清除缓存';

  @override
  String get settingsClearCacheSubtitle => '清除临时文件和缓存';

  @override
  String get settingsManageModels => '管理模型';

  @override
  String get settingsManageModelsSubtitle => '下载、更新或删除转录模型';

  @override
  String get settingsStorageBreakdown => '存储详情';

  @override
  String get settingsStorageBreakdownSubtitle => '查看各后端磁盘占用并释放空间';

  @override
  String get storageTitle => '存储详情';

  @override
  String get storageRefresh => '刷新';

  @override
  String get storageEmpty => '磁盘上暂无模型文件。';

  @override
  String get storageTotalUsed => '磁盘总占用';

  @override
  String storageBackendCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个后端',
    );
    return '$_temp0';
  }

  @override
  String storageFilesCount(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
    );
    return '$size · $_temp0';
  }

  @override
  String get storageDeleteAllTooltip => '删除此后端的所有模型';

  @override
  String storageDeleteTitle(String backend) {
    return '删除所有 $backend 模型？';
  }

  @override
  String storageDeleteMessage(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
    );
    return '这将释放 $size，共 $_temp0，且无法撤销。';
  }

  @override
  String get storageDeleteConfirm => '删除';

  @override
  String storageDeletedSnack(String size) {
    return '已释放 $size';
  }

  @override
  String get settingsDebugging => '调试与开发';

  @override
  String get settingsLogLevel => '日志级别';

  @override
  String settingsLogLevelCurrent(String level) {
    return '当前：$level';
  }

  @override
  String get settingsMirrorLogs => '镜像日志到文件';

  @override
  String get settingsMirrorLogsSubtitle => '写入应用文档目录下的 logs/session.log';

  @override
  String get settingsSkipChecksum => '跳过校验和验证';

  @override
  String get settingsSkipChecksumSubtitle => '即使 SHA-1 不匹配也接受已下载的模型';

  @override
  String get settingsSkipMemoryPreflight => '跳过内存预检';

  @override
  String get settingsSkipMemoryPreflightSubtitle =>
      '即使预估内存超出本机容量也开始长音频转录。可能导致系统冻结。';

  @override
  String get advancedSensitivityPreset => '灵敏度预设';

  @override
  String get advancedSensitivityPresetHelper => '将下方四个阈值作为一组调整。“手动”则保留各个滑块。';

  @override
  String get advancedSensitivityManual => '手动';

  @override
  String get advancedSensitivityConservative => '保守';

  @override
  String get advancedSensitivityBalanced => '平衡';

  @override
  String get advancedSensitivityAggressive => '激进';

  @override
  String get settingsGroupBatchByBackend => '按后端分组批处理';

  @override
  String get settingsGroupBatchByBackendSubtitle => '对队列文件重新排序，使连续任务复用同一模型会话';

  @override
  String get settingsMaxConcurrent => '并发转录数';

  @override
  String settingsMaxConcurrentCurrent(int n) {
    return '并发转录数：$n';
  }

  @override
  String get settingsMaxConcurrentSessions => '并行会话数';

  @override
  String settingsMaxConcurrentSessionsCurrent(int n) {
    return '并行会话数：$n';
  }

  @override
  String get settingsMaxConcurrentSessionsSubtitle =>
      '1 = 单会话（默认）。2 或以上将启动 N 个 Worker 隔离，每个持有独立的模型副本。代价是 N × 模型大小；启动前会检查设备内存是否足够。';

  @override
  String settingsMemoryProjection(String projected, String total, String per) {
    return '预计 RAM：$projected（共 $total，每 Worker：$per）';
  }

  @override
  String settingsMemoryProjectionClamped(int affordable, int requested) {
    return '已限制为 $affordable 个 Worker（请求 $requested 个）— 模型过大，可用 RAM 不足';
  }

  @override
  String batchResumedSnackbar(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '已恢复 $n 个中断的转录',
      one: '已恢复 1 个中断的转录',
    );
    return '$_temp0 — 点击「开始」以继续';
  }

  @override
  String get settingsMaxConcurrentSubtitle =>
      '1 = 串行（当前行为）。2 或以上将在转录当前文件时，在 Worker 隔离中预解码下一个文件的音频 — 无需额外模型副本。';

  @override
  String get settingsOpenLogViewer => '打开日志查看器';

  @override
  String get settingsSpeakers => '说话人';

  @override
  String get settingsSpeakersSubtitle => '注册声纹，以便在分离中自动标注说话人姓名。';

  @override
  String get speakersTitle => '说话人';

  @override
  String get speakersEmpty => '尚未注册说话人。点击 + 添加。';

  @override
  String get speakersPrivacyNote => '声纹仅存储在设备本地，不会上传。';

  @override
  String get speakersDownloadModelHint => '请先在模型管理中下载 TitaNet 模型，再进行注册。';

  @override
  String get speakersAdd => '添加说话人';

  @override
  String get speakersDeleteTitle => '删除已注册的说话人？';

  @override
  String speakersDeleteBody(String name) {
    return '$name 的声纹将从此设备中删除。';
  }

  @override
  String get speakersDeleteFailed => '删除声纹失败。';

  @override
  String get speakersEnrolTitle => '注册说话人';

  @override
  String get speakersSourceRecord => '录音';

  @override
  String get speakersSourceFile => '选择文件';

  @override
  String get speakersName => '说话人姓名';

  @override
  String get speakersNameRequired => '姓名不能为空';

  @override
  String get speakersNameTaken => '已存在同名说话人。';

  @override
  String get speakersNoSample => '请先录制或选择一个音频样本。';

  @override
  String get speakersEnrolButton => '注册';

  @override
  String get speakersEnrolFailed => '注册失败 — 请尝试更清晰的样本。';

  @override
  String get speakersRecord => '开始录音';

  @override
  String get speakersRecordStop => '停止';

  @override
  String speakersRecordHint(int seconds) {
    return '点击录制此人说话的 $seconds 秒样本。';
  }

  @override
  String speakersRecordingCountdown(int seconds) {
    return '录音中… 剩余 $seconds 秒';
  }

  @override
  String speakersRecordingDone(int seconds) {
    return '已录制 $seconds 秒音频。';
  }

  @override
  String get speakersRecordNoPermission => '麦克风权限被拒绝。';

  @override
  String get speakersPickHint => '选择包含此人清晰说话声音的任意音频文件。';

  @override
  String get speakersPickButton => '选择音频文件';

  @override
  String get settingsSystemInfo => '系统信息';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsAboutCrisperWeaver => '关于 CrisperWeaver';

  @override
  String get settingsAboutCrisperWeaverSubtitle => '作者、联系方式、免责声明、许可证';

  @override
  String get settingsHfTokenTitle => 'Hugging Face API 令牌';

  @override
  String get settingsHfTokenSubtitle => '访问门控或私有仓库时必填。';

  @override
  String get settingsHfTokenSave => '保存';

  @override
  String get settingsHfTokenCancel => '取消';

  @override
  String get transcriptionNoModelsFound => '未找到模型';

  @override
  String get transcriptionRetry => '重试';

  @override
  String transcriptionLoadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String transcriptionSavedTo(String path) {
    return '已保存至 $path';
  }

  @override
  String transcriptionSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get transcriptionCopiedToClipboard => '已复制到剪贴板';

  @override
  String get transcriptionShareSheetTitle => '分享或保存';

  @override
  String get transcriptionSharePlainText => '分享纯文本';

  @override
  String get transcriptionCopyToClipboard => '复制到剪贴板';

  @override
  String get transcriptionSaveAsTxt => '保存为 TXT';

  @override
  String get transcriptionSaveAsSrt => '保存为 SRT';

  @override
  String get transcriptionSaveAsVtt => '保存为 VTT';

  @override
  String get transcriptionSaveAsJson => '保存为 JSON';

  @override
  String get transcriptionDownloadModel => '下载模型';

  @override
  String get transcriptionDownload => '下载';

  @override
  String get advancedBestOfSingle => '最优解码：单次解码 (1)';

  @override
  String advancedBestOfCurrent(int n) {
    return '最优解码：$n 次';
  }

  @override
  String get advancedBestOfHelper =>
      '1 = 单次解码（默认）。大于 1 时运行 N 次独立解码并选取得分最高的结果。代价为 N 倍解码时间。';

  @override
  String get advancedTemperatureGreedy => '解码温度：贪婪 (0.00)';

  @override
  String advancedTemperatureCurrent(String value) {
    return '解码温度：$value';
  }

  @override
  String get advancedTemperatureHelper =>
      '0.00 = 贪婪/可复现。大于 0 = 随机采样 — 当贪婪解码出现重复幻觉时有用。Whisper 有内置回退梯队；此项影响采样后端（canary、cohere、parakeet、moonshine）。';

  @override
  String downloadModelPrompt(String name, String size) {
    return '模型「$name」尚未下载。是否立即下载（约 $size）？';
  }

  @override
  String get tooltipDeleteRecording => '删除录音';

  @override
  String get tooltipUseForTranscription => '用于转录';

  @override
  String get tooltipModelSelectionHelp => '模型选择帮助';

  @override
  String get tooltipDownloadModel => '下载模型';

  @override
  String get tooltipDisplayLevel => '显示级别';

  @override
  String get tooltipPauseAutoScroll => '暂停自动滚动';

  @override
  String get tooltipResumeAutoScroll => '恢复自动滚动';

  @override
  String get labelApiToken => 'API 令牌';

  @override
  String get streamingRequiresWhisper => '实时转录需要 Whisper 引擎。请在设置中切换后端。';

  @override
  String get streamingMicUnavailable => '麦克风不可用，无法进行实时转录。';

  @override
  String get streamingEngineNoSession => '引擎未返回流式会话。';

  @override
  String playbackFailed(String error) {
    return '播放失败：$error';
  }

  @override
  String synthesizeFailed(String error) {
    return '合成失败：$error';
  }

  @override
  String logsShowLevel(String level) {
    return '显示 $level 及以上';
  }

  @override
  String get diarizationAuto => '自动';

  @override
  String get diarizationModelSelectionTitle => '分离模型选择';

  @override
  String get aboutServiceProvider => '服务提供商';

  @override
  String get aboutContact => '联系方式';

  @override
  String get aboutPrivacy => '隐私';

  @override
  String get aboutDisclaimer => '免责声明';

  @override
  String get aboutLicense => '许可证';

  @override
  String get aboutOpenSourceLicenses => '开源许可证';

  @override
  String get aboutPrivacyText =>
      'CrisperWeaver 在您的设备本地处理所有音频。音频数据、转录内容和录音均不会上传至任何服务器。模型下载通过 HTTPS 直接从 HuggingFace 获取 GGUF 权重文件；其他任何数据均不离开设备。';

  @override
  String get aboutDisclaimerText =>
      '本软件按「现状」提供，不附带任何形式的明示或暗示保证，包括但不限于适销性、特定用途适用性及不侵权保证。在任何情况下，作者均不对因使用或无法使用本软件而产生的任何索赔、损害或其他责任承担责任。';

  @override
  String get aboutLicenseText =>
      'CrisperWeaver 是自由软件，依据 GNU Affero 通用公共许可证 v3.0（AGPL-3.0）授权。您可以在该许可证条款下重新发布和修改本软件。特别是，如果您以网络服务形式运行修改版 CrisperWeaver，必须向其用户提供源代码。';

  @override
  String get historyTitle => '转录历史';

  @override
  String get historyEmpty => '暂无转录记录';

  @override
  String get historyEmptyHint => '运行转录后将显示在此处。';

  @override
  String get historyRefresh => '刷新';

  @override
  String get historyClearAll => '全部清除';

  @override
  String get historySearchHint => '搜索标题或转录内容…';

  @override
  String historySearchNoResults(String query) {
    return '没有与「$query」匹配的历史记录';
  }

  @override
  String historySearchMatchCount(int matched, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      matched,
      locale: localeName,
      other: '共 $total 条，匹配 $matched 条',
    );
    return '$_temp0';
  }

  @override
  String get historyClearAllPrompt => '将从此设备删除所有保存的转录记录，此操作无法撤销。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get logsTitle => '日志';

  @override
  String get logsFilterHint => '按消息、标签或错误筛选…';

  @override
  String get logsCopyVisible => '复制可见内容';

  @override
  String get logsCopyAll => '复制全部';

  @override
  String get logsExport => '导出到文件';

  @override
  String get logsShare => '作为文件分享';

  @override
  String get modelsTitle => '模型管理';

  @override
  String get modelsNoneAvailable => '暂无可用模型';

  @override
  String get modelsRetry => '重试';

  @override
  String get modelsDownload => '下载';

  @override
  String get modelsDelete => '删除模型';

  @override
  String get modelsDownloaded => '已下载';

  @override
  String get modelsNotDownloaded => '未下载';

  @override
  String modelsDownloadingPercent(String percent) {
    return '下载中… $percent%';
  }

  @override
  String get error => '错误';

  @override
  String get ok => '确定';

  @override
  String get save => '保存';

  @override
  String get done => '完成';

  @override
  String get settingsSaved => '设置已保存';

  @override
  String get settingsDefaultBackend => '默认后端';

  @override
  String get settingsSelectBackend => '选择默认后端';

  @override
  String settingsSelectModel(String backend) {
    return '选择默认模型（$backend）';
  }

  @override
  String get settingsSelectLanguage => '选择默认语言';

  @override
  String get settingsSelectInterfaceLanguage => '选择界面语言';

  @override
  String settingsNoModelsForBackend(String backend) {
    return '后端「$backend」暂无已知模型。请使用模型管理器 → 云下载图标探测 HuggingFace。';
  }

  @override
  String get modelFilterHint => '按名称/量化类型筛选模型';

  @override
  String get modelAnyBackend => '任意后端';

  @override
  String get modelNoMatch => '没有匹配此筛选条件的模型。';

  @override
  String get modelsRefreshFromHf => '从 HuggingFace 刷新量化版本';

  @override
  String get modelsReloadLocal => '重新加载本地状态';

  @override
  String get modelsQuickStartTooltip => '快速开始';

  @override
  String get quickStartTitle => '快速开始';

  @override
  String get quickStartSubtitle => '一键获取小型入门套装 — 转录、语音合成和文本整理。';

  @override
  String get quickStartDownloadAll => '下载所有缺失项';

  @override
  String get quickStartInstalled => '已安装';

  @override
  String get quickStartAllInstalled => '所有入门模型均已安装。';

  @override
  String get modelsProbedCountZero => '在 HuggingFace 上未发现新的量化版本。';

  @override
  String modelsProbedCount(int count, String plural) {
    return '发现 $count 个新量化版本$plural。';
  }

  @override
  String get batchQueueTitle => '批量队列';

  @override
  String batchQueueSummary(int queued, int running, int done, int errored) {
    return '$queued 排队 · $running 运行中 · $done 完成 · $errored 失败';
  }

  @override
  String get batchClearCompleted => '清除已完成';

  @override
  String get batchRemove => '从队列中移除';

  @override
  String batchEnqueueAdded(int count) {
    return '已添加 $count 个文件到队列。';
  }

  @override
  String get batchRunAll => '全部转录';

  @override
  String get batchStop => '停止批处理';

  @override
  String get batchQueueDropHint => '将音频文件拖放至此处加入队列';

  @override
  String get advancedSection => '高级解码';

  @override
  String get advancedSectionTooltip =>
      '控制模型将音频转成文字的方式。默认值适合大多数录音——仅在转写结果不理想时才需要调整。';

  @override
  String get advancedVadTrim => '静音裁剪（VAD）';

  @override
  String get advancedVadTrimSubtitle =>
      '通过 Silero VAD 跳过开头和结尾的静音。对含大量静音的会议/长录音更快。';

  @override
  String get advancedTranslate => '翻译为英语';

  @override
  String get advancedTranslateSubtitle => '仅 Whisper — 强制输出英语，忽略源语言。';

  @override
  String get advancedBeamSearch => '束搜索';

  @override
  String get advancedBeamSearchSubtitle => '速度较慢，通常更准确。默认使用贪婪解码。';

  @override
  String advancedBeamSize(int n) {
    return 'Beam 宽度：$n';
  }

  @override
  String get advancedBeamSizeHelper => 'Beam 搜索的 beam 数量。0 = 后端默认值（通常为 5）。';

  @override
  String advancedHotwordsBoost(String value) {
    return '热词增强：$value';
  }

  @override
  String get advancedHotwordsBoostHelper =>
      'CTC/TDT 热词偏置增强因子（granite、parakeet）。0 = 关闭。';

  @override
  String advancedChunkSeconds(int n) {
    return '分块窗口：$n秒';
  }

  @override
  String get advancedChunkSecondsHelper =>
      '转录分块大小（秒）。0 = 模型默认值（约30秒）。较小的值可减少长文件的峰值内存占用。';

  @override
  String get advancedInitialPrompt => '初始提示（词汇/上下文）';

  @override
  String get advancedInitialPromptHint =>
      '例如：\"CrispASR, Flutter, Riverpod, 说话人区分\"';

  @override
  String get advancedInitialPromptHelper =>
      '模型在处理音频前先读取的上下文：人名、术语或希望采用的写法。Whisper 类模型会使用它；CTC 模型（Parakeet、Canary、Wav2Vec2）会忽略。';

  @override
  String get advancedRestorePunctuation => '恢复标点（FireRedPunc）';

  @override
  String get advancedRestorePunctuationSubtitle =>
      '对原始输出进行大写和标点处理。适用于 CTC 后端（wav2vec2、fastconformer-ctc、firered-asr）。需在模型管理中下载 fireredpunc-*.gguf。';

  @override
  String get advancedSourceLanguage => '源语言（覆盖自动检测）';

  @override
  String get advancedSourceLanguageAuto => '自动 / 使用主选择器';

  @override
  String get advancedSourceLanguageHelper =>
      '当 Whisper 自动检测在嘈杂音频中不可靠时，可固定源语言。留空则回退到主语言下拉列表/自动检测。';

  @override
  String get advancedTargetLanguage => '翻译目标语言';

  @override
  String get advancedTargetLanguageNone => '不翻译（原文转录）';

  @override
  String get advancedTargetLanguageHelper =>
      '仅对支持翻译的后端显示（Canary、Voxtral、Qwen3、Cohere、Whisper）。原文转录时保持「不翻译」。';

  @override
  String get advancedAskPrompt => '提问音频（问答模式）';

  @override
  String get advancedAskPromptHint => '例如：「摘要」或「做出了什么决定？」';

  @override
  String get advancedAskPromptHelper =>
      '仅限 Voxtral / Qwen3-ASR。设置后，LLM 将回答您的问题而非生成逐字转录，且该回答在任何导出中都会标记为 AI 生成。留空则正常转录。涉及说话人情绪、心情、语气或意图的提问将被拒绝——参见使用规范。';

  @override
  String get askPromptRefusedAffectiveTitle => '提问被拒绝';

  @override
  String askPromptRefusedAffective(String term) {
    return '该提问要求模型推断说话人的情绪或意图属性（匹配到「$term」）。从声音推断情绪属于欧盟《人工智能法案》所定义的情绪识别——在工作场所和学校中被禁止，在其他场合属于高风险。CrisperWeaver 不执行此类推断。请提问「说了什么」，而非「听起来如何」。';
  }

  @override
  String get editAudioOpen => '在音频编辑器中打开';

  @override
  String get editAudioTitle => '编辑音频';

  @override
  String editAudioLoadFailed(String error) {
    return '无法解码音频：$error';
  }

  @override
  String get editAudioSaveAs => '另存编辑后的音频为…';

  @override
  String editAudioSavedTo(String path) {
    return '已保存至 $path';
  }

  @override
  String get editAudioTrim => '裁剪';

  @override
  String get editAudioCut => '剪切中段';

  @override
  String get editAudioAddSplitMark => '添加分割标记';

  @override
  String editAudioRunSplit(int n) {
    return '分割为 $n 个文件';
  }

  @override
  String get editAudioClearMarks => '清除标记';

  @override
  String get editAudioClearSelection => '清除选区';

  @override
  String get editAudioNeedSelection => '请先在波形上拖动选择一个区域。';

  @override
  String get editAudioNeedSplitMarks => '请先添加至少一个分割标记。';

  @override
  String editAudioSelectionLabel(String start, String end) {
    return '选区：$start – $end';
  }

  @override
  String editAudioSplitSaved(int n) {
    return '已保存 $n 个文件。';
  }

  @override
  String get editAudioHowto =>
      '点击波形定位。拖动选择区域。使用「裁剪」保留 [开始, 结束]；「剪切中段」删除 [开始, 结束] 并拼接其余部分；「添加分割标记」在当前播放头添加分割点，然后「分割」将每个区域写为一个 WAV 文件。';

  @override
  String get editAudioToggleTranscriptShow => '显示转录';

  @override
  String get editAudioToggleTranscriptHide => '隐藏转录';

  @override
  String get editAudioTranscriptHeading => '转录';

  @override
  String get editAudioTranscriptEmpty => '尚无转录。请先转录音频，然后返回此处用于导航和剪切区域标记。';

  @override
  String get editAudioTranscriptSegmentTapHint => '点击行定位播放头。长按行查看剪切/裁剪选项。';

  @override
  String get editAudioMarkSegmentForCut => '标记片段为分割点';

  @override
  String get editAudioTrimToSegment => '裁剪至此片段';

  @override
  String get editAudioSelectSegment => '选择此片段';

  @override
  String editAudioSegmentMarkedForCut(String time) {
    return '已在 $time 处标记分割点。';
  }

  @override
  String get close => '关闭';

  @override
  String get presetsTooltip => '预设';

  @override
  String get presetsTitle => '预设';

  @override
  String get presetsHelp => '将当前后端、模型、语言和高级选项保存为命名预设，稍后一键还原所有设置。';

  @override
  String get presetsSaveCurrent => '将当前设置保存为预设';

  @override
  String get presetsSaveCurrentTitle => '保存预设';

  @override
  String get presetsNameLabel => '预设名称';

  @override
  String get presetsNameHint => '例如：播客准备、语音备忘、多语种采访';

  @override
  String get presetsEmpty => '暂无预设。保存当前设置即可开始。';

  @override
  String get presetsApply => '应用';

  @override
  String presetsApplied(String name) {
    return '已应用预设「$name」。';
  }

  @override
  String get presetsRenameTitle => '重命名预设';

  @override
  String get presetsRenameTooltip => '重命名';

  @override
  String get presetsDeleteTitle => '删除预设？';

  @override
  String presetsDeleteConfirm(String name) {
    return '删除预设「$name」？此操作无法撤销。';
  }

  @override
  String get presetsDeleteTooltip => '删除';

  @override
  String get outputSummarize => '摘要…';

  @override
  String get outputOcrImage => '图片OCR…';

  @override
  String get outputRealignTimestamps => '重新对齐时间戳';

  @override
  String get outputDetectLanguage => '检测语言';

  @override
  String get outputSummarizeTitle => '转录摘要';

  @override
  String outputSummarizeHelp(String model) {
    return '将转录内容发送给 $model 并请求结构化摘要。输出为 Markdown 格式的要点列表。';
  }

  @override
  String get outputSummarizeUnconfigured =>
      '未配置云端 LLM 端点。请前往设置 → 云端 LLM 整理添加端点 — 整理和摘要使用同一端点。';

  @override
  String get outputSummarizeKindActionItems => '行动项';

  @override
  String get outputSummarizeKindKeyTopics => '关键主题';

  @override
  String get outputSummarizeKindDecisions => '决策';

  @override
  String get outputSummarizeRun => '生成摘要';

  @override
  String get outputSummarizeEmpty => '请选择部分并运行。';

  @override
  String get outputSummarizeNothing => '模型未为所选部分返回任何项目。';

  @override
  String get outputCleanup => '整理转录…';

  @override
  String get outputCleanupTitle => '整理转录';

  @override
  String get outputCleanupHelp => '对常见 ASR 瑕疵进行确定性清理。选择要应用的选项，预览结果，然后全部应用。';

  @override
  String get outputCleanupRemoveFillers => '删除填充词（嗯、啊、呃…）';

  @override
  String get outputCleanupCollapseRepeats => '合并重复词（那那 → 那）';

  @override
  String get outputCleanupSentenceCase => '句首字母大写';

  @override
  String get outputCleanupFixPunctuation => '修正标点（……，双逗号，多余句点）';

  @override
  String get outputCleanupNormalizeWhitespace => '规范化空白';

  @override
  String get outputCleanupStripAnnotations => '去除注释标签';

  @override
  String get outputCleanupStripAnnotationsHelp =>
      '删除 [笑声]、(掌声)、<噪音> 等标注。默认关闭 — 对无障碍访问有用。';

  @override
  String get outputCleanupCustomFillers => '自定义填充词';

  @override
  String get outputCleanupCustomFillersHint => '逗号或空格分隔，例如：像、基本上、你知道';

  @override
  String get outputCleanupPreviewHeading => '预览（前 3 个片段）';

  @override
  String get outputCleanupPreviewEmpty => '无可预览的片段。';

  @override
  String get outputCleanupApply => '全部应用';

  @override
  String get outputCleanupLlmPass => '同时运行 LLM 处理（云端）';

  @override
  String outputCleanupLlmPassHelp(String model) {
    return '在确定性处理后，将每个片段发送给 $model 进行上下文感知清理。较慢；使用已配置的 API 密钥。';
  }

  @override
  String get outputCleanupLlmPassUnconfigured => '请在设置 → 云端 LLM 整理中配置端点以启用此功能。';

  @override
  String get outputCleanupLlmRunning => '正在运行 LLM 云端清理…';

  @override
  String get outputCleanupLlmMode => 'LLM 模式';

  @override
  String get outputCleanupLlmModeOff => '关闭';

  @override
  String get outputCleanupLlmModeCloud => '云端';

  @override
  String get outputCleanupLlmModeLocal => '本地';

  @override
  String outputCleanupLlmModeCloudHelp(String model) {
    return '在确定性处理后，将每个片段发送给 $model（云端，BYOK）。较慢；使用已配置的 API 密钥。';
  }

  @override
  String outputCleanupLlmModeLocalHelp(String model) {
    return '在确定性处理后，在此设备上通过 $model 处理每个片段。无需网络，无需 API 密钥；首次运行时将模型加载到内存。';
  }

  @override
  String get outputCleanupLlmModeCloudUnconfigured =>
      '请在设置 → 云端 LLM 整理中配置端点以启用此功能。';

  @override
  String get outputCleanupLlmModeLocalUnconfigured =>
      '请在设置 → 本地 LLM 整理中指定 GGUF 对话模型以启用此功能。';

  @override
  String get settingsLocalLlmCleanup => '本地 LLM 整理（设备端）';

  @override
  String get settingsLocalLlmCleanupOff => '关闭（指定 GGUF 对话模型以启用）';

  @override
  String get settingsLocalLlmHelp =>
      '可选。在此设备上加载 GGUF 对话模型，并对每次整理/摘要请求运行该模型。无需网络，无需 API 密钥。根据模型大小需要约 2–8 GB 可用 RAM；支持时使用 Metal / CUDA 加速。';

  @override
  String get settingsLocalLlmModelPath => '对话模型文件（GGUF）';

  @override
  String get settingsLocalLlmModelPathEmpty => '未选择模型';

  @override
  String get settingsLocalLlmModelPick => '浏览…';

  @override
  String get settingsLocalLlmModelClear => '清除';

  @override
  String get settingsLocalLlmAdvanced => '高级参数';

  @override
  String settingsLocalLlmNGpuLayers(int n) {
    return 'GPU 层数：$n';
  }

  @override
  String get settingsLocalLlmNGpuLayersAll => 'GPU 层数：全部';

  @override
  String get settingsLocalLlmNGpuLayersHelp =>
      '-1 = 将所有层卸载到 GPU（默认；macOS 使用 Metal / Linux+Windows 使用 CUDA）。0 = 仅 CPU。正数为低 VRAM 设备的部分卸载。';

  @override
  String settingsLocalLlmNCtx(int n) {
    return '上下文窗口（词元）：$n';
  }

  @override
  String get settingsLocalLlmNCtxDefault => '上下文窗口：模型默认';

  @override
  String get settingsLocalLlmNCtxHelp => '0 保持 GGUF 内置默认值。摘要长转录时可提高；内存受限时可降低。';

  @override
  String settingsLocalLlmNThreads(int n) {
    return 'CPU 线程数：$n';
  }

  @override
  String get settingsLocalLlmNThreadsAuto => 'CPU 线程数：自动';

  @override
  String settingsLocalLlmMaxTokens(int n) {
    return '每次调用最大输出词元：$n';
  }

  @override
  String settingsLocalLlmTemperature(String t) {
    return '温度：$t';
  }

  @override
  String get settingsLocalLlmUnsupported =>
      '此 libcrispasr 构建不支持对话 ABI — 需要 CrispASR 0.7.0 或更新版本。';

  @override
  String get outputCleanupLocalLlmRunning => '正在运行本地 LLM 清理…';

  @override
  String get outputCleanupLocalLlmLoading => '正在加载本地 LLM（首次运行可能需要几秒）…';

  @override
  String get settingsHotkey => '全局快捷键';

  @override
  String get settingsHotkeyOff => '关闭（配置组合键和行为后启用）';

  @override
  String get settingsHotkeyHelp =>
      '注册系统级键盘快捷键，无需将应用切换到前台即可开始/停止录音。仅限桌面端 — iOS / Android 不支持全局快捷键。';

  @override
  String get settingsHotkeyEnable => '启用全局快捷键';

  @override
  String get settingsHotkeyCombo => '键组合';

  @override
  String get settingsHotkeyBehavior => '行为';

  @override
  String get settingsHotkeyActionPushToTalk => '按住说话';

  @override
  String get settingsHotkeyActionPushToTalkHelp =>
      '按住录音，松开停止。与包含修饰键的组合键配合使用效果最佳（如 meta+shift+space）。';

  @override
  String get settingsHotkeyActionToggle => '切换';

  @override
  String get settingsHotkeyActionToggleHelp => '按一次开始，再按一次停止。操作更简单，无需持续按住修饰键。';

  @override
  String settingsHotkeyInvalid(String combo) {
    return '无效的组合键「$combo」。请使用 修饰键+修饰键+按键 格式，如 meta+shift+space。';
  }

  @override
  String get settingsCloudLlmCleanup => '云端 LLM 整理（BYOK）';

  @override
  String get settingsCloudLlmCleanupOff => '关闭（粘贴 OpenAI 兼容 URL + API 密钥以启用）';

  @override
  String get settingsCloudLlmHelp =>
      '可选。将每个片段发送到 OpenAI 兼容的 /v1/chat/completions 端点进行上下文感知清理。支持 OpenAI、通过代理的 Anthropic、OpenRouter、Groq、本地 llama-server 等。密钥仅存储在本设备。';

  @override
  String get settingsCloudLlmUrl => 'API URL';

  @override
  String get settingsCloudLlmKey => 'API 密钥';

  @override
  String get settingsCloudLlmModel => '模型 ID';

  @override
  String get settingsCloudLlmClear => '清除';

  @override
  String outputCleanupApplied(int n) {
    return '已对 $n 个片段应用整理。';
  }

  @override
  String get outputEditSegmentInAudioEditor => '在音频编辑器中编辑此片段';

  @override
  String get outputMarkSegmentInAudioEditor => '在音频编辑器中标记为分割点';

  @override
  String editAudioSegmentSelected(String start, String end) {
    return '已设置选区：$start – $end。';
  }

  @override
  String advancedMaxLen(int n) {
    return '每片段最大词元数：$n';
  }

  @override
  String get advancedMaxLenOff => '关闭';

  @override
  String get advancedMaxLenSubtitle =>
      '仅 Whisper 软上限。0 = 不限（默认）。与「按词边界分割」配合使用，可生成 SRT 友好的短字幕行。';

  @override
  String get advancedSplitOnWord => '按词边界分割';

  @override
  String get advancedSplitOnWordSubtitle => '达到片段上限时，在下一个词边界而非词中间断开，生成更易读的字幕。';

  @override
  String get advancedSplitOnPunct => '按标点分割';

  @override
  String get advancedSplitOnPunctSubtitle =>
      '在句末标点（. ! ?）处分割片段，生成自然的字幕行。支持所有后端。';

  @override
  String get advancedVocabulary => '自定义词汇';

  @override
  String get advancedVocabularyHint => '输入术语后按回车（如：API、kubectl、Alice）';

  @override
  String get advancedVocabularyAdd => '添加术语';

  @override
  String get advancedVocabularyHelperPrompt =>
      '通过 Whisper 的 initial_prompt 偏向解码器。适用于模型容易听错的品牌名、缩写、技术术语和人名。';

  @override
  String get advancedVocabularyHelperAsk =>
      '通过在提示前附加这些术语来偏向 LLM。与问答模式结合 — 问题仍会执行。';

  @override
  String get advancedVocabularyHelperUnsupported =>
      '当前后端为 CTC 式，无法在解码器处偏向词汇。请切换到 Whisper / Moonshine / LLM 后端（Voxtral、Qwen3、Granite…）以启用。';

  @override
  String get advancedHotwords => '热词';

  @override
  String get advancedHotwordsHint => '逗号分隔的词或短语（如：ACME 公司、TensorFlow、张医生）';

  @override
  String get advancedHotwordsHelper => '引导解码器偏向这些词/短语。适用于模型容易听错的名称、品牌或领域术语。';

  @override
  String get advancedHotwordsUnsupported =>
      '当前后端不支持热词偏向。请切换到 LLM 后端或 Whisper 以启用。';

  @override
  String get voiceCloneOpenTooltip => '克隆声音…';

  @override
  String get voiceCloneTitle => '声音克隆向导';

  @override
  String get voiceCloneStepCapture => '录制';

  @override
  String get voiceCloneStepRefText => '参考文本';

  @override
  String get voiceCloneStepHandoff => '合成';

  @override
  String get voiceCloneCaptureHeading => '录制参考片段';

  @override
  String voiceCloneCaptureHelp(int seconds) {
    return '录制约 $seconds 秒清晰的语音，或选择现有音频文件。单一说话人、背景噪音少的录音克隆效果最佳。';
  }

  @override
  String get voiceCloneCaptureNoPermission => '麦克风权限被拒绝。请在系统设置中授予权限后重试。';

  @override
  String voiceCloneRecord(int seconds) {
    return '录制 $seconds 秒';
  }

  @override
  String get voiceClonePickFile => '选择文件';

  @override
  String voiceCloneRecordingCountdown(int seconds) {
    return '剩余 $seconds 秒';
  }

  @override
  String get voiceCloneRecordingStop => '停止';

  @override
  String get voiceClonePreviewPlay => '播放';

  @override
  String get voiceClonePreviewPause => '暂停';

  @override
  String get voiceCloneCaptureClear => '重新开始';

  @override
  String get voiceCloneNonWavWarning =>
      '该文件不是 WAV。只有 chatterbox 支持从其他格式克隆；qwen3-tts、IndexTTS、VibeVoice、F5-TTS 等都需要 WAV，会拒绝此片段。请在此处录制，或先转换为单声道 16/24 kHz WAV。';

  @override
  String get voiceCloneRefTextHeading => '片段中说了什么？';

  @override
  String get voiceCloneRefTextHelp =>
      'Qwen3-TTS Base 和 CosyVoice3 没有逐字转录就无法克隆；indextts / vibevoice 用它进行对齐。chatterbox 和 F5-TTS 仅从音频即可克隆。拿不准时就填写 — 准确的转录不会有坏处。';

  @override
  String get voiceCloneRefTextLabel => '参考转录';

  @override
  String get voiceCloneRefTextHint => '输入参考片段中说的内容…';

  @override
  String get voiceCloneHandoffHeading => '准备合成';

  @override
  String get voiceCloneHandoffHelp =>
      '我们将打开合成界面，并预填充片段和参考文本。选择支持克隆的模型（chatterbox、indextts、qwen3-tts Base、vibevoice-1.5b），输入要朗读的文本，然后点击「合成」。';

  @override
  String get voiceCloneHandoffModelHint =>
      '提示：chatterbox / F5-TTS 仅从音频克隆；qwen3-tts Base 和 CosyVoice3 必须提供参考转录；indextts / vibevoice 在提供时会使用它。';

  @override
  String get voiceCloneSummaryReference => '参考片段';

  @override
  String get voiceCloneSummaryRefText => '参考文本';

  @override
  String get voiceCloneSummaryRefTextEmpty => '（无 — 纯音频克隆）';

  @override
  String get voiceCloneBack => '返回';

  @override
  String get voiceCloneNext => '下一步';

  @override
  String get voiceCloneConsentTitle => '声音权利确认';

  @override
  String get voiceCloneConsentBody =>
      '语音克隆会创建参考音频中声音的合成复制品。根据欧盟AI法案（第50条）和GDPR（第9条），您必须获得声音所有者的明确同意，或该声音必须是您自己的。禁止滥用语音克隆进行身份冒充。';

  @override
  String get voiceCloneConsentCheckbox =>
      '我确认我有权克隆此声音（这是我自己的声音，或我已获得声音所有者的明确同意）';

  @override
  String get voiceCloneFinish => '在合成中打开';

  @override
  String get synthTitle => '合成';

  @override
  String get synthModelLabel => 'TTS 模型';

  @override
  String get synthVoiceLabel => '音色/声音包';

  @override
  String get synthCodecLabel => '编解码器/分词器';

  @override
  String get synthTextHint => '输入要合成的文本…';

  @override
  String get synthDiaTextHint => '[S1] 你好，你还好吗？[S2] 我很好，谢谢！';

  @override
  String get synthDiaHelper =>
      'Dia 使用 [S1] 和 [S2] 标签标记对话中的不同说话人。使用 100 个字符以上的提示可获得最佳效果。';

  @override
  String get synthS2sToggle => '语音转语音模式';

  @override
  String get synthS2sHelper => '通过模型转换音频输入，而非从文本合成。需要 LFM2-Audio 或 Mini-Omni2。';

  @override
  String get synthS2sPickAudio => '未选择音频文件';

  @override
  String get synthS2sBrowse => '浏览';

  @override
  String get synthRunButton => '合成';

  @override
  String get synthPlayButton => '播放';

  @override
  String get synthStopButton => '停止';

  @override
  String get synthShareButton => '保存/分享 WAV';

  @override
  String get synthNoTtsModelsDownloaded =>
      '尚未下载 TTS 模型。请前往模型 → 模型选项卡 → 切换到「TTS」获取一个。';

  @override
  String get synthOpenModelManagement => '打开模型管理';

  @override
  String defaultModelNotDownloaded(String modelId) {
    return '默认模型「$modelId」尚未下载。';
  }

  @override
  String get noModelsDownloadedYet => '尚未下载任何转录模型 — 请打开模型页面获取一个。';

  @override
  String get filePickerCloudFileUnsupported =>
      '此文件存储在云端，无法直接打开。请将其复制到本地存储（设备的「下载」或「文件」），然后重试。';

  @override
  String filePickerFailed(String error) {
    return '文件选择器失败：$error';
  }

  @override
  String get openModels => '打开模型';

  @override
  String synthMissingDependency(String name) {
    return '缺少必需的配套文件：$name';
  }

  @override
  String synthBackendUnsupported(String backend) {
    return '此构建版本中 $backend 合成功能尚不可用。更新版引擎发布后此声音将可用。';
  }

  @override
  String get synthSpeakerLabel => '说话人';

  @override
  String get synthSpeakerHelper => '此声音内置多个说话人 — 请选择一个。';

  @override
  String get synthPreviewVoice => '预览声音';

  @override
  String get synthPreviewSample => '你好，这是语音预览。';

  @override
  String get advancedVadBackend => 'VAD 后端';

  @override
  String get advancedVadBackendHelper =>
      'Silero 已内置（约 885 KB）。FireRed / MarbleNet / Whisper-VAD 需在模型管理中下载；缺少文件时回退到 Silero。';

  @override
  String get advancedVadBackendSilero => 'Silero（内置，默认）';

  @override
  String get advancedVadBackendFirered => 'FireRedVAD（F1 97.57%，约 3 MB）';

  @override
  String get advancedVadBackendMarblenet => 'MarbleNet（小型，多语言）';

  @override
  String get advancedVadBackendWhisperEncDec => 'Whisper-VAD-EncDec（实验性英语）';

  @override
  String advancedVadThreshold(String value) {
    return 'VAD 阈值：$value';
  }

  @override
  String get advancedVadThresholdHelper =>
      '越高 = 检测到的语音区域越少/越短。CrispASR 默认值为 0.50。';

  @override
  String advancedVadMinSpeech(int ms) {
    return '最短语音时长：$ms ms';
  }

  @override
  String get advancedVadMinSpeechHelper => '保留为语音片段的最短有声片段。';

  @override
  String advancedVadMinSilence(int ms) {
    return '最短静音时长：$ms ms';
  }

  @override
  String get advancedVadMinSilenceHelper => '将一个片段与下一个片段分开的最短静音。';

  @override
  String advancedVadSpeechPad(int ms) {
    return '语音填充：$ms ms';
  }

  @override
  String get advancedVadSpeechPadHelper => '在每个语音片段两侧添加的额外上下文。';

  @override
  String get advancedLidMethod => '语言检测方法';

  @override
  String get advancedLidMethodHelper =>
      '当模型不支持原生 LID 且您选择了「自动」时使用。Whisper 复用任意多语言 ggml-*.bin；Silero / Firered / Ecapa 各需其自身的 GGUF。';

  @override
  String get advancedLidMethodWhisper => 'Whisper 编码器（复用现有模型）';

  @override
  String get advancedLidMethodSilero => 'Silero（95 种语言，约 16 MB GGUF）';

  @override
  String get advancedLidMethodFirered => 'FireRed（120 种语言，约 300 MB GGUF）';

  @override
  String get advancedLidMethodEcapa => 'ECAPA-TDNN（107 种语言，约 42 MB GGUF）';

  @override
  String get advancedAlignerModel => '词级时间戳对齐模型';

  @override
  String get advancedAlignerModelAuto => '自动（选择最佳可用）';

  @override
  String get advancedAlignerModelHelper =>
      '当转写模型本身不输出词级时间戳时，用它补齐。“自动”优先选择与语言匹配的 Wav2Vec2 模型，否则使用 Canary CTC 对齐模型。';

  @override
  String get advancedGrammarTitle => 'GBNF 语法（仅 Whisper）';

  @override
  String get advancedGrammarSubtitle =>
      '强制输出特定结构（JSON / SKU / 电话号码 / …）。留空 = 不约束。';

  @override
  String get advancedGrammarSubtitleActive => '语法已激活 — 输出将受此 GBNF 约束。';

  @override
  String get advancedGrammarTextLabel => 'GBNF 源码';

  @override
  String get advancedGrammarTextHelper =>
      '用于限制解码器输出内容的 GBNF 规则。普通转写请留空；规则无效会导致本次运行报错中止。';

  @override
  String get advancedGrammarRootRule => '根规则';

  @override
  String get advancedGrammarRootRuleHelper => '开始解析的符号名称。GBNF 约定为「root」。';

  @override
  String advancedGrammarPenalty(String value) {
    return '语法惩罚：$value';
  }

  @override
  String get advancedGrammarPenaltyHelper =>
      '越高 = 约束越硬，越低 = 约束越软。上游默认值为 100；有效范围 50..200。';

  @override
  String get advancedTranscribeWindowTitle => '转录窗口（偏移量 + 时长）';

  @override
  String get advancedTranscribeWindowSubtitle =>
      '仅处理音频的 [开始, 开始+时长) 片段。留空 / 0 = 转录整个文件（默认）。';

  @override
  String advancedTranscribeWindowSubtitleActive(String start, String end) {
    return '已激活：文件的 ${start}s..${end}s。时间戳在输出中保持绝对值。';
  }

  @override
  String get advancedTranscribeWindowEndOfFile => '文件末尾';

  @override
  String get advancedTranscribeWindowStart => '开始（秒）';

  @override
  String get advancedTranscribeWindowStartHelper => '文件中的偏移量。0 = 从头开始。';

  @override
  String get advancedTranscribeWindowDuration => '时长（秒）';

  @override
  String get advancedTranscribeWindowDurationHelper => '0 = 转录至文件末尾。';

  @override
  String get advancedFallbackThresholdsTitle => 'Whisper 解码器回退';

  @override
  String get advancedFallbackThresholdsSubtitle =>
      '调整解码器以更高温度重试或将音频视为静音的时机。默认值与原版 whisper.cpp 一致。';

  @override
  String get advancedFallbackThresholdsSubtitleActive =>
      '自定义阈值已激活 — 默认值为 2.4 / -1.0 / 0.6 / 0.2。';

  @override
  String get advancedFallbackThresholdsReset => '重置为默认值';

  @override
  String advancedEntropyThold(String value) {
    return '熵阈值：$value';
  }

  @override
  String get advancedEntropyTholdHelper =>
      '触发回退的每词元熵值。默认 2.4。越低 = 越严格（对困难音频多次重试）；越高 = 减少过多重试。';

  @override
  String advancedLogprobThold(String value) {
    return '对数概率阈值：$value';
  }

  @override
  String get advancedLogprobTholdHelper =>
      '触发回退的平均对数概率截止值。默认 -1.0。更负 = 对嘈杂解码更宽容。';

  @override
  String advancedNoSpeechThold(String value) {
    return '无语音阈值：$value';
  }

  @override
  String get advancedNoSpeechTholdHelper =>
      '静音检测截止值。默认 0.6。越高 = 静音门控越不激进（保留微弱语音）。';

  @override
  String advancedTemperatureInc(String value) {
    return '温度增量：$value';
  }

  @override
  String get advancedTemperatureIncDisabled => '温度增量：0（回退已禁用）';

  @override
  String get advancedTemperatureIncHelper =>
      '每次回退的温度步长。默认 0.2。设为 0 可完全禁用回退循环（相当于 CLI 的 --no-fallback）。';

  @override
  String get advancedWhisperDecodeExtrasTitle => 'Whisper 文本抑制';

  @override
  String get advancedWhisperDecodeExtrasSubtitle =>
      '丢弃非语音标记、通过正则表达式抑制词元，或在每个解码窗口重复初始提示。';

  @override
  String get advancedWhisperDecodeExtrasSubtitleActive =>
      '自定义抑制已激活 — 默认：保留所有词元 / 无正则 / 单窗口提示。';

  @override
  String get advancedSuppressNonSpeechTokens => '丢弃非语音词元';

  @override
  String get advancedSuppressNonSpeechTokensHelper =>
      '去除 Whisper 在口语内容上方发出的 [LAUGHTER] / [MUSIC] / [NOISE] 标记。默认关闭。';

  @override
  String get advancedSuppressTokensRegex => '抑制正则（Posix）';

  @override
  String get advancedSuppressTokensRegexHelper =>
      '文本匹配此正则的词元在解码期间被丢弃。留空禁用。适用于清除幻觉词元或说话人标签模式。';

  @override
  String get advancedCarryInitialPrompt => '在每个窗口携带初始提示';

  @override
  String get advancedCarryInitialPromptHelper =>
      '在每个解码窗口开始时重复初始提示（不仅限于第一个）。以减弱前一上下文条件为代价，加强长音频上的词汇偏向。';

  @override
  String get advancedEnhanceAudio => '增强音频（降噪）';

  @override
  String get advancedEnhanceAudioHelper =>
      '在转录前对音频运行 RNNoise 预处理。减少暖通空调 / 风扇 / 键盘噪音。CPU 上约消耗 1× 实时时间；默认关闭。';

  @override
  String get settingsLocalLlmCatalogueTitle => '推荐对话模型';

  @override
  String get settingsLocalLlmCatalogueHelp =>
      '点击已下载的模型进行选择。点击未下载的模型可打开模型管理并下载。';

  @override
  String get settingsLocalLlmCatalogueManage => '管理';

  @override
  String settingsLocalLlmCatalogueDownloaded(String size) {
    return '已下载 · $size';
  }

  @override
  String settingsLocalLlmCatalogueNotDownloaded(String size) {
    return '未下载 · $size';
  }

  @override
  String get settingsLocalLlmCatalogueDownload => '下载';

  @override
  String get modelsKindFilterChatLlm => '对话 LLM';

  @override
  String get advancedDiarizeMethod => '分离方法';

  @override
  String get advancedDiarizeMethodHelper =>
      '仅在启用分离时生效。vad-turns 适合单声道；pyannote 需要其分割 GGUF；energy / xcorr 需要立体声音频。';

  @override
  String get advancedDiarizeVadTurns => 'VAD 轮换（单声道，无需额外模型）';

  @override
  String get advancedDiarizePyannote => 'Pyannote v3（机器学习，需要 GGUF）';

  @override
  String get advancedDiarizeEnergy => '立体声左/右能量';

  @override
  String get advancedDiarizeXcorr => '立体声互相关';

  @override
  String get advancedDiarizeFoxnose => 'FoxNose（WeSpeaker 声纹嵌入，需要 GGUF）';

  @override
  String get advancedSpeakerRecognition => '识别已注册说话人';

  @override
  String get advancedSpeakerRecognitionSubtitle =>
      '分离后，将每个说话人聚类与设备上的说话人数据库（设置 → 说话人）比对，有把握时将「说话人 N」替换为注册姓名。需要 TitaNet GGUF。';

  @override
  String get advancedTdrz => 'Tinydiarize 说话人轮换（仅 Whisper）';

  @override
  String get advancedTdrzSubtitle =>
      '通过 Whisper .en.tdrz 微调插入 [SPEAKER_TURN] 标记。会话后端不生效。';

  @override
  String get advancedTokenTimestamps => '词元级时间戳';

  @override
  String get advancedTokenTimestampsSubtitle =>
      'DTW 对齐的每词元计时。比词级时间戳慢；适用于精细字幕工具。';

  @override
  String get advancedAltN => '每词备选候选数（仅 Whisper）';

  @override
  String advancedAltNLabel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '前 $n 个',
      zero: '关闭',
    );
    return '$_temp0';
  }

  @override
  String get advancedAltNSubtitle =>
      '捕获 Whisper 每个贪婪步骤的前 N 个备选词元。可在转录编辑器中点击模糊词并选择竞争候选项（kubectl / cubicle / …）。0 = 关闭（默认）。最适合贪婪解码 — 不支持束搜索。0.5.13 之前的 dylib 静默忽略。';

  @override
  String get advancedPuncFamily => '标点模型';

  @override
  String get advancedPuncFamilyHelper =>
      'PCS 一体化（标点 + 真实大小写 + SBD，47 种语言）。FireRedPunc 和 fullstop-punc 与真实大小写器配合使用。';

  @override
  String get advancedPuncFamilyPcs => 'PCS（47 种语言，一体化）';

  @override
  String get advancedPuncFamilyFirered => 'FireRedPunc（中文 + 英语）';

  @override
  String get advancedPuncFamilyFullstop => 'Fullstop-punc 多语言（EN/DE/FR/IT）';

  @override
  String get transcriptionSaveAsCsv => '保存为 CSV';

  @override
  String get transcriptionSaveAsLrc => '保存为 LRC（歌词）';

  @override
  String get transcriptionSaveAsWts => '保存为 WTS（调试）';

  @override
  String get transcriptionSaveAsMarkdown => '保存为 Markdown';

  @override
  String get transcriptionShareAudioAndTranscript => '分享音频 + 转录';

  @override
  String get transcriptionShareAudioAndTranscriptHelp =>
      '将音频文件和 SRT 转录作为单次分享发送 — 便于归档或交接给同事。';

  @override
  String get transcriptionShareAudioMissing => '请先选择音频文件以一起分享。';

  @override
  String get synthAdvancedSection => '高级合成';

  @override
  String get synthRefText => '参考转录（声音克隆）';

  @override
  String get synthRefTextHelper =>
      '将 WAV 声音与 qwen3-tts Base 或 vibevoice-1.5b 配合进行运行时克隆时必填。内置 GGUF 声音无需填写。';

  @override
  String get synthInstruct => '声音描述（VoiceDesign / Parler-TTS）';

  @override
  String get synthInstructHelper =>
      '所需声音的自然语言描述（「温暖的女性旁白，轻微英式口音」）。供 qwen3-tts VoiceDesign 和 Parler-TTS 使用；其他后端忽略。';

  @override
  String get synthTrimSilence => '裁剪静音';

  @override
  String get synthTrimSilenceSubtitle => '从合成 PCM 中裁剪低于 -72 dBFS 的开头和结尾静音。';

  @override
  String synthSpeed(String value) {
    return '速度：$value×';
  }

  @override
  String get synthSpeedHelper => '播放速度倍率（0.25× – 4.00×）。最近邻重采样；无音调校正。';

  @override
  String get translateTitle => '文本翻译';

  @override
  String get translateModelLabel => '翻译模型';

  @override
  String get translateSourceLang => '源语言';

  @override
  String get translateTargetLang => '目标语言';

  @override
  String get translateSwap => '交换源语言和目标语言';

  @override
  String get translateInputLabel => '原文';

  @override
  String get translateInputHint => '输入或粘贴要翻译的文本…';

  @override
  String get translateOutputLabel => '译文';

  @override
  String get translateRunButton => '翻译';

  @override
  String get translateNoModelsDownloaded =>
      '未下载翻译模型。请打开模型，切换到「翻译」筛选，并获取 M2M-100、WMT21（en→X / X→en）或 MADLAD-400 之一。';

  @override
  String get translateAdvanced => '高级';

  @override
  String translateMaxTokens(int n) {
    return '最大输出词元数：$n';
  }

  @override
  String get translateMaxTokensHelper =>
      '翻译文本长度的硬上限。CrispASR 默认值为 200；较长段落可提高，较短生成可降低。';

  @override
  String get advancedPerfHeader => '性能';

  @override
  String get advancedLidUseGpu => 'GPU 语言检测';

  @override
  String get advancedLidUseGpuSubtitle =>
      '在支持时将语言检测路由到 Metal / CUDA / Vulkan。ASR 后端在加载时遵循其自身的每会话 GPU 设置。';

  @override
  String get advancedLidFlashAttn => 'LID 闪速注意力';

  @override
  String get advancedLidFlashAttnSubtitle =>
      '在 LID 编码器过程中使用更快的注意力内核。仅在怀疑构建版本存在闪速注意力正确性问题时禁用。';

  @override
  String advancedNThreads(int n) {
    return 'CPU 线程数：$n';
  }

  @override
  String get advancedNThreadsHelper => '用于 LID 和其他非解码器过程的线程数。默认为 4。';

  @override
  String get synthCustomVoice => '自定义声音（WAV 参考）';

  @override
  String get synthCustomVoiceHelper =>
      '从磁盘选择 WAV 进行运行时克隆。在 qwen3-tts Base / vibevoice-1.5b 上与参考转录配合使用。设置后覆盖声音包下拉列表。';

  @override
  String get synthCustomVoicePick => '选择参考 WAV…';

  @override
  String get synthCustomVoiceReplace => '替换参考 WAV…';

  @override
  String get synthCustomVoiceClear => '清除自定义声音';

  @override
  String synthCloneReferenceActive(String file) {
    return '正在从 $file 克隆';
  }

  @override
  String synthCloneModelCannotClone(String model) {
    return '$model 无法从参考片段克隆声音 — 它只接受已下载的声音包。请选择支持克隆的模型（chatterbox、IndexTTS、Qwen3-TTS Base、VibeVoice 1.5B、F5-TTS），或清除参考片段。';
  }

  @override
  String synthCloneNeedsRefText(String model) {
    return '$model 需要参考片段的转录文本。请在「高级 → 参考转录」中输入片段内容，然后重新合成。';
  }

  @override
  String synthCloneNeedsWav(String model) {
    return '$model 只能从 WAV 参考克隆。请将片段转换为单声道 16 或 24 kHz WAV，或在声音克隆向导中重新录制。';
  }

  @override
  String synthCloneReferenceMissing(String file) {
    return '参考片段 $file 已不在磁盘上。请重新选择或录制一个新的。';
  }

  @override
  String synthCloneNonAsciiPath(String file) {
    return '在 Windows 上，音频引擎无法打开路径含非英文字符的文件。请将 $file 复制到纯 ASCII 路径的文件夹（例如 C:\\voices\\）后重新选择。';
  }

  @override
  String get synthCloneNoCapableModel =>
      '已下载的 TTS 模型都无法克隆声音。请先在模型管理中下载 chatterbox、IndexTTS、Qwen3-TTS Base、VibeVoice 1.5B 或 F5-TTS。';

  @override
  String get recorderStreamSession => '流式（会话）';

  @override
  String get recorderStreamSessionTooltip =>
      '通过活跃后端的流式接口进行实时麦克风转录（kyutai-stt / moonshine-streaming / voxtral4b）。后端无原生流式 API 时回退到 Whisper 滑动窗口。';

  @override
  String streamingNotAvailableForBackend(String backend) {
    return '活跃后端（$backend）无流式接口。请切换到 whisper、kyutai-stt、moonshine-streaming 或 voxtral4b。';
  }

  @override
  String get streamingNoModelLoaded =>
      '尚未加载模型。请从上方下拉列表选择一个模型（已下载则自动加载），或先打开模型管理下载一个。';

  @override
  String get transcribeNoSource => '请选择音频文件、输入 URL 或进行录音。';

  @override
  String get voiceBakeTitle => '烘焙声音（WAV → GGUF）';

  @override
  String get voiceBakeOpenTooltip => '从 WAV 参考烘焙 Chatterbox 声音';

  @override
  String get voiceBakeIntro =>
      '运行 CrispASR 的 bake-chatterbox-voice-from-wav.py，将 WAV 参考转换为烘焙声音包 GGUF。需要系统上安装 Python 3 + chatterbox-tts + gguf。';

  @override
  String get voiceBakeWavLabel => '参考 WAV';

  @override
  String get voiceBakeWavPick => '选择 WAV…';

  @override
  String get voiceBakeOutputName => '输出文件名';

  @override
  String get voiceBakeOutputNameHelper => '保存到模型目录中其他声音包旁边。使用 .gguf 扩展名。';

  @override
  String voiceBakeExaggeration(String value) {
    return '夸张度：$value';
  }

  @override
  String get voiceBakeExaggerationHelper => '默认情绪推进标量（0.0 – 1.0）。0.5 为上游默认值。';

  @override
  String get voiceBakePythonLabel => 'Python 解释器';

  @override
  String get voiceBakePythonHelper =>
      '默认为 PATH 中的 `python3`。如果 chatterbox-tts / gguf 安装在 venv 中，请覆盖此项。';

  @override
  String get voiceBakeScriptLabel => '烘焙脚本路径';

  @override
  String get voiceBakeScriptHelper =>
      '默认为 ../CrispASR/models/bake-chatterbox-voice-from-wav.py。如果 CrispASR 检出目录不同，请调整。';

  @override
  String get voiceBakeRun => '烘焙声音';

  @override
  String get voiceBakeRunning => '烘焙中…';

  @override
  String voiceBakeSuccess(String path) {
    return '声音已烘焙 → $path';
  }

  @override
  String voiceBakeFailure(String error) {
    return '烘焙失败：$error';
  }

  @override
  String get voiceBakeMissingInputs => '请先选择参考 WAV 和输出文件名。';

  @override
  String get advancedAsrUseGpu => 'GPU ASR';

  @override
  String get advancedAsrUseGpuSubtitle =>
      '在支持时将 ASR 会话初始化路由到 Metal / CUDA / Vulkan。下次模型加载时生效。无运行时 GPU 控制的后端保持编译时默认设置。';

  @override
  String get advancedAsrFlashAttn => 'ASR 闪速注意力';

  @override
  String get advancedAsrFlashAttnSubtitle =>
      '在 ASR 计算图中使用闪速注意力内核。Whisper 原生支持；其他后端接受此切换，但其计算图尚未分支于此。下次模型加载时生效。';

  @override
  String advancedAsrNGpuLayers(int n) {
    return 'GPU 层数（LLM）：$n';
  }

  @override
  String get advancedAsrNGpuLayersAuto => 'GPU 层数（LLM）：自动（最大值）';

  @override
  String get advancedAsrNGpuLayersHelper =>
      '基于 LLM 的后端（orpheus / voxtral / qwen3 / granite / chatterbox）GPU 卸载 Transformer 层上限。0 = 在 CPU 上运行 LLM；1+ = 明确边界；自动 = 尽量多。下次模型加载时生效。';

  @override
  String get settingsServerSection => '本地 HTTP 服务器（OpenAI 兼容）';

  @override
  String get settingsServerEnable => '运行服务器';

  @override
  String settingsServerRunningAt(String url) {
    return '正在监听 $url';
  }

  @override
  String get settingsServerStopped => '已停止。打开开关可在本地端口上公开 CrisperWeaver 的服务。';

  @override
  String settingsServerStartFailed(String error) {
    return '服务器启动失败：$error';
  }

  @override
  String get settingsServerEndpoints => '端点';

  @override
  String get settingsServerEndpointsHelp =>
      'POST /v1/audio/transcriptions（多部分上传，file=音频）· POST /v1/audio/speech（JSON：model、input、voice、speed）· POST /v1/translations（JSON：model、text、src、tgt）· GET /health。仅绑定到 127.0.0.1 — 无需身份验证。';

  @override
  String synthTemperature(String value) {
    return '温度：$value';
  }

  @override
  String get synthTemperatureHelper =>
      'orpheus / chatterbox / canary 共享的采样温度。0.0 = 贪婪/可复现。越高 = 多样性越大。';

  @override
  String synthTtsSteps(int n) {
    return '扩散步数：$n';
  }

  @override
  String get synthTtsStepsHelper =>
      'chatterbox mel 解码器中 CFM Euler 步数（默认 10）。越高 = 音频越平滑，但延迟越大。';

  @override
  String synthCfgWeight(String value) {
    return 'CFG 权重：$value';
  }

  @override
  String get synthCfgWeightHelper =>
      '无分类器引导权重（chatterbox）。0 禁用 CFG；0.5 为上游默认值；1+ 放大条件路径。';

  @override
  String synthExaggeration(String value) {
    return '夸张度：$value';
  }

  @override
  String get synthExaggerationHelper =>
      '情绪夸张标量（chatterbox）。0.5 为上游默认值；调高可增加戏剧感，调低则更单调。';

  @override
  String synthTopP(String value) {
    return 'Top-p：$value';
  }

  @override
  String get synthTopPHelper =>
      'Top-p 核采样阈值（chatterbox）。1.0 禁用 top-p；降低可截断低概率词元的长尾。';

  @override
  String synthMinP(String value) {
    return 'Min-p：$value';
  }

  @override
  String get synthMinPHelper =>
      'Min-p 阈值（chatterbox）。0 禁用；正值丢弃概率低于最可能词元此比例的词元。';

  @override
  String synthRepetitionPenalty(String value) {
    return '重复惩罚：$value';
  }

  @override
  String get synthRepetitionPenaltyHelper =>
      '重复惩罚标量（chatterbox）。1.0 禁用；调高可阻止模型在重复词元上循环卡顿。';

  @override
  String synthMaxSpeechTokens(int n) {
    return '最大语音词元数：$n';
  }

  @override
  String get synthMaxSpeechTokensHelper =>
      '每次调用 AR 语音词元的硬上限（chatterbox）。1000 ≈ 20 秒；长文本可提高，防止失控生成可降低。';

  @override
  String synthSeed(int n) {
    return '种子：$n';
  }

  @override
  String get synthSeedHelper =>
      '可复现输出的随机种子（chatterbox、vibevoice、qwen3-tts、orpheus）。0 = 不确定。';

  @override
  String synthFrequencyPenalty(String value) {
    return '频率惩罚：$value';
  }

  @override
  String get synthFrequencyPenaltyHelper =>
      '对自回归后端中重复词元进行惩罚。0 = 关闭；调高可减少循环卡顿瑕疵。';

  @override
  String synthTopK(int n) {
    return 'Top-K：$n';
  }

  @override
  String get synthTopKHelper =>
      'Top-K 采样宽度（qwen3-tts、chatterbox、orpheus、dots-tts、tada）。0 = 禁用。';

  @override
  String get synthDoSample => '随机采样';

  @override
  String get synthDoSampleHelper => '启用随机采样代替贪心解码。';

  @override
  String synthNumCandidates(int n) {
    return '声学候选数：$n';
  }

  @override
  String get synthNumCandidatesHelper =>
      '用于排序的声学候选数（tada、chatterbox、kokoro）。0 = 默认值。';

  @override
  String synthNoiseTemp(String value) {
    return '噪声温度：$value';
  }

  @override
  String get synthNoiseTempHelper => '随机生成的噪声温度（kokoro、vibevoice）。0 = 默认值。';

  @override
  String get synthG2pDict => 'G2P 字典';

  @override
  String get synthG2pDictHelper => '字形到音素字典路径（kokoro、vibevoice、speecht5）。';

  @override
  String get synthClearPhonemeCache => '清除音素缓存';

  @override
  String get synthClearPhonemeCacheDone => '音素缓存已清除。';

  @override
  String get synthClearPhonemeCacheUnsupported => '此后端不使用音素缓存（或当前会话过旧）。';

  @override
  String modelsLoadFailed(String error) {
    return '加载模型失败：$error';
  }

  @override
  String modelsProbeFailed(String error) {
    return 'HuggingFace 探测失败：$error';
  }

  @override
  String modelsSkippedRepos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个私有/门控仓库',
    );
    return ' 已跳过 $_temp0。';
  }

  @override
  String get modelsHfRepoTitle => '从 HuggingFace 仓库添加';

  @override
  String get modelsHfRepoAddTooltip => '从 HuggingFace 仓库添加…';

  @override
  String get modelsHfReposManageTooltip => '管理已添加的 HuggingFace 仓库…';

  @override
  String get modelsHfRepoBody =>
      '粘贴 HuggingFace 仓库 ID，如「cstr/voxtral-mini-3b-2507-GGUF」。CrisperWeaver 将列出仓库中所有 .gguf / .bin 文件，将每个注册为您选择后端下的可下载模型，并添加到模型列表。';

  @override
  String get modelsHfRepoIdLabel => '仓库 ID（OWNER/NAME）';

  @override
  String get modelsHfRepoIdHint => '例如：cstr/voxtral-mini-3b-2507-GGUF';

  @override
  String get modelsHfRepoBackendLabel => '后端';

  @override
  String get modelsHfRepoBackendHelper => '模型的加载方式。';

  @override
  String get modelsHfRepoProbe => '探测';

  @override
  String modelsHfRepoNoneFound(String repo) {
    return '在 $repo 中未找到 .gguf / .bin 文件。';
  }

  @override
  String modelsHfRepoAdded(int count, String repo) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个模型',
    );
    return '已从 $repo 添加 $_temp0。';
  }

  @override
  String modelsHfRepoProbeFailed(String repo, String error) {
    return '探测 $repo 失败：\n$error';
  }

  @override
  String get modelsHfReposTitle => '已添加的 HuggingFace 仓库';

  @override
  String get modelsHfReposEmpty =>
      '尚未添加仓库。使用「从 HuggingFace 仓库添加…」注册一个 — 将在重启后保留。';

  @override
  String modelsHfRepoBackendValue(String backend) {
    return '后端：$backend';
  }

  @override
  String get modelsHfRepoForget => '忘记此仓库';

  @override
  String get modelsAnyLanguage => '任意语言';

  @override
  String get modelsCategoryEmpty => '此类别暂无模型 — 请尝试云刷新按钮，或先从其他类别下载一个。';

  @override
  String get modelsFilterAll => '全部';

  @override
  String get modelsFilterAsr => 'ASR';

  @override
  String get modelsFilterTts => 'TTS';

  @override
  String get modelsFilterVoices => '声音';

  @override
  String get modelsFilterCodecs => '编解码器';

  @override
  String get modelsFilterPostproc => '后处理器';

  @override
  String get modelsFilterTranslate => '翻译';

  @override
  String get modelsFilterAllLangs => '所有语言';

  @override
  String modelsDownloadedOne(String name) {
    return '$name 已下载';
  }

  @override
  String modelsDownloadedMany(int count, String names) {
    return '已下载 $count 个文件：$names';
  }

  @override
  String modelsDeletedNamed(String name) {
    return '$name 已删除';
  }

  @override
  String modelsTotalSize(String size) {
    return '总大小：$size';
  }

  @override
  String modelsDownloadFailedNamed(String name) {
    return '下载 $name 失败';
  }

  @override
  String modelsDownloadFailedReason(String error) {
    return '下载失败：$error';
  }

  @override
  String modelsDeleteFailedNamed(String name) {
    return '删除 $name 失败';
  }

  @override
  String modelsDeleteFailedReason(String error) {
    return '删除失败：$error';
  }

  @override
  String get enrollFromSegment => '从此片段注册说话人…';

  @override
  String get enrollSpeakerTitle => '注册说话人';

  @override
  String get enrollSpeakerNameLabel => '说话人姓名';

  @override
  String get enrollSpeakerNameHint => '例如：张伟';

  @override
  String get enrollAction => '注册';

  @override
  String get enrollInProgress => '注册中…';

  @override
  String get enrollNoAudio => '此片段无音频可注册。';

  @override
  String enrollSucceeded(String name) {
    return '已注册「$name」 — 未来录音将进行匹配。';
  }

  @override
  String get enrollFailedShort => '注册失败。';

  @override
  String enrollFailedReason(String error) {
    return '注册失败：$error';
  }

  @override
  String get modelsRecommendedBadge => '推荐';

  @override
  String transcribeNoBackendModelHint(String backend) {
    return '尚未下载 $backend 模型。';
  }

  @override
  String transcribeDownloadRecommended(String name, String size) {
    return '推荐下载：$name（$size）';
  }

  @override
  String synthDownloadingNamed(String name) {
    return '正在下载 $name…';
  }

  @override
  String synthDownloadFailedShort(String name) {
    return '下载 $name 失败';
  }

  @override
  String synthDownloadFailedNamed(String name, String error) {
    return '下载 $name 失败：$error';
  }

  @override
  String get aiGeneratedAudio => 'AI 生成音频';

  @override
  String get speakerConsentTitle => '生物特征数据同意';

  @override
  String get speakerConsentBody =>
      '说话人注册会创建声纹嵌入（GDPR 第 9 条下的生物特征数据）。此数据仅存储在您的设备上，绝不传输，并可随时从说话人管理界面删除。\n\n如果该声音不属于您本人，您必须在注册前获得该人的明确同意。只有具备同意记录的说话人才会参与匹配。\n\n继续操作即表示您确认该声音为您本人所有，或您已获得声音所有者的明确同意（GDPR 第 9(2)(a) 条）。';

  @override
  String get speakerConsentAgree => '我确认';

  @override
  String get aboutSyntheticCompliance => '合成内容合规';

  @override
  String get aboutSyntheticComplianceText =>
      '合成语音输出带有水印并包含机器可读的来源元数据。说话人注册需要明确的生物特征同意（GDPR 第 9 条）。所有数据留在设备上；您可以随时删除您的数据。';

  @override
  String get syntheticDisclosureNote => '此内容包含 AI 生成的合成语音。';

  @override
  String get aiTransparencyTitle => 'AI 驱动的应用程序';

  @override
  String get aiTransparencyBody =>
      'CrisperWeaver 使用人工智能系统进行：\n\n• 语音识别 (ASR) — 将音频转换为文本\n• 语音合成 (TTS) — 从文本生成语音音频\n• 说话人识别 — 生物特征语音匹配\n• 文档分析 (OCR) — 识别图像中的文字\n• 文本生成 — 由语言模型进行翻译、摘要和转录稿整理\n• 音频问答 — 由语言模型回答您关于录音的提问，而非转录内容\n• 说话人分离 — 区分谁在何时说话 — 以及口语语种检测\n• 音频增强 — 降噪处理\n• 语义搜索 — AI 驱动的内容检索\n\n默认情况下，所有处理均在您的设备上运行，不会发送任何数据。部分功能默认关闭，启用后会使用网络：模型下载、可选的云端转录，以及可选的云端摘要或整理功能，它们会将相关文本或音频发送至您所配置的服务商。说话人档案和语音录音永远不会离开您的设备。\n\nAI 生成的音频会自动添加水印并签署机器可读的来源元数据；AI 生成的文本在复制或导出时会附带披露声明（欧盟AI法案第50条）。\n\n详情请参见关于页面及 PRIVACY.md。';

  @override
  String get aiTransparencyWebNote =>
      '网页版说明：与桌面版和移动版不同，浏览器版本没有设备端引擎。语音识别和语音合成在远程 CrispASR 服务器上运行，因此您提交的音频会被发送至该服务器处理。用于搜索的文本嵌入仍在您的浏览器本地计算。';

  @override
  String get aiTransparencyAcknowledge => '我了解';

  @override
  String get historySearchSemanticTooltip => '语义搜索（已激活）';

  @override
  String get historySearchSubstringTooltip => '子串搜索（点击切换为语义搜索）';

  @override
  String get historyCompareButton => '比较…';

  @override
  String get historyCompareNoOtherEntries => '没有其他可比较的条目';

  @override
  String get historyComparePickerTitle => '与…比较';

  @override
  String get menuCompareModels => '比较模型';

  @override
  String get menuSubtitleOverlay => '字幕叠加';

  @override
  String get advancedTagSegmentLanguages => '标注片段语言';

  @override
  String get advancedTagSegmentLanguagesSubtitle => '按片段检测语言（多语言）';

  @override
  String get exportObsidian => 'Obsidian';

  @override
  String get exportNotion => 'Notion';

  @override
  String get exportLogseq => 'Logseq';

  @override
  String get exportYouTubeChapters => 'YouTube 章节';

  @override
  String get exportDetectChapters => '检测章节';

  @override
  String get exportPodcastChapters => '播客章节（JSON）';

  @override
  String get compareModelsNeedSecond => '请下载第二个模型以进行比较';

  @override
  String get compareModelsPickerTitle => '与模型比较…';

  @override
  String compareModelsRunning(String modelA, String modelB) {
    return '正在运行 A/B：$modelA 与 $modelB…';
  }

  @override
  String compareModelsFailed(String error) {
    return 'A/B 测试失败：$error';
  }

  @override
  String get settingsWatchFolder => '监控文件夹';

  @override
  String get settingsWatchFolderAutoTranscribe => '自动转录新文件';

  @override
  String settingsWatchFolderWatching(String path) {
    return '正在监控：$path';
  }

  @override
  String get settingsWatchFolderMonitorHint => '监控文件夹以检测新音频文件';

  @override
  String get settingsWatchFolderPath => '监控文件夹路径';

  @override
  String get settingsWatchFolderNotSet => '未设置';

  @override
  String get settingsWatchFolderPickerTitle => '选择要监控的文件夹';

  @override
  String get settingsWatchFolderUnavailable => '无法再读取此文件夹。请重新选择以恢复监控。';

  @override
  String get settingsSpeakerVocab => '说话人词汇';

  @override
  String get settingsSpeakerVocabSubtitle => '每位说话人的领域词汇列表';

  @override
  String get settingsSpeakerVocabDialogTitle => '说话人词汇';

  @override
  String settingsSpeakerVocabAddTermTitle(String name) {
    return '为 $name 添加术语';
  }

  @override
  String get settingsSpeakerVocabAddTermHint => '领域词汇或短语';

  @override
  String get settingsSpeakerVocabNoSpeakers => '无已注册说话人。请先在说话人管理界面注册说话人。';

  @override
  String get add => '添加';

  @override
  String get synthLexiconSectionTitle => '发音词典';

  @override
  String get synthLexiconAddTitle => '添加发音';

  @override
  String get synthLexiconAddEntryTooltip => '添加条目';

  @override
  String get synthLexiconWordLabel => '词语';

  @override
  String get synthLexiconWordHint => '例如：CrispASR';

  @override
  String get synthLexiconPronunciationLabel => '发音';

  @override
  String get synthLexiconPronunciationHint => '例如：Crisp A S R';

  @override
  String get synthLexiconIpaLabel => 'IPA 标注';

  @override
  String get synthLexiconEmpty => '暂无条目。请添加词语 → 发音映射。';

  @override
  String get outputSegmentEditedTooltip => '已编辑';

  @override
  String get subtitleExitOverlayTooltip => '退出叠加';

  @override
  String get subtitleSmallerTextTooltip => '缩小文字';

  @override
  String get subtitleLargerTextTooltip => '放大文字';

  @override
  String get subtitleTogglePositionTooltip => '切换位置';

  @override
  String get subtitleToggleBackgroundTooltip => '切换背景';

  @override
  String get subtitleWaitingForTranscription => '等待转录…';

  @override
  String get compareTranscriptsTitle => '比较转录';

  @override
  String get compareLeftFallback => '左';

  @override
  String get compareRightFallback => '右';

  @override
  String get compareLeftWords => '左侧单词数';

  @override
  String get compareRightWords => '右侧单词数';

  @override
  String get compareSimilarity => '相似度';

  @override
  String get abTestNeedSecondModel => '请下载第二个模型以进行比较';

  @override
  String get abTestPickModel => '与模型比较…';

  @override
  String abTestRunning(String modelA, String modelB) {
    return '正在运行 A/B：$modelA 与 $modelB…';
  }

  @override
  String abTestFailed(String error) {
    return 'A/B 测试失败：$error';
  }

  @override
  String get subtitleOverlayExitTooltip => '退出叠加';

  @override
  String get subtitleOverlaySmallerText => '缩小文字';

  @override
  String get subtitleOverlayLargerText => '放大文字';

  @override
  String get subtitleOverlayTogglePosition => '切换位置';

  @override
  String get subtitleOverlayToggleBackground => '切换背景';

  @override
  String get subtitleOverlayWaiting => '等待转录…';

  @override
  String get outputNoTranscriptionYet => '暂无转录';

  @override
  String get outputSelectAudioFile => '选择音频文件并开始转录';

  @override
  String get outputNoResultsFound => '未找到结果';

  @override
  String get outputTryDifferentSearch => '请尝试其他搜索词';

  @override
  String get outputEdited => '已编辑';

  @override
  String get outputLidModelNeeded =>
      '请下载文本语言识别模型（CLD3、GlotLID 或 FastText LID-176）以检测语言。';

  @override
  String get outputLidModelsButton => '模型';

  @override
  String get outputLidFailed => '语言检测失败。';

  @override
  String outputLidDetected(String code, String pct, String model) {
    return '检测到语言：$code（$pct%）[$model]';
  }

  @override
  String get outputTagSegment => '标注片段';

  @override
  String get dialogCancel => '取消';

  @override
  String get dialogAdd => '添加';

  @override
  String get dialogApply => '应用';

  @override
  String get settingsAllFilesAccessNeeded => '需要「所有文件访问」权限';

  @override
  String get settingsAllFilesAccessExplanation =>
      '选择应用沙箱外的文件夹需要 Android 的「所有文件访问」权限。点击「打开设置」，为 CrisperWeaver 启用「所有文件访问」，然后返回。卸载并重新安装应用后，Android 将重置此授权，需重新启用。';

  @override
  String get settingsOpenSettings => '打开设置';

  @override
  String get settingsAllFilesAccessDenied => '「所有文件访问」被拒绝 — 改为使用沙箱目录。';

  @override
  String get fingerprintDedupTitle => '已转录';

  @override
  String get fingerprintDedupBody => '此文件已被转录。是否再次转录？';

  @override
  String get fingerprintDedupTranscribeAgain => '再次转录';

  @override
  String get modelsRecommendedHeader => '建议从这些开始';

  @override
  String modelsAllHeader(int count) {
    return '全部模型（$count）';
  }

  @override
  String get modelsTooLargeTitle => '超出本设备可加载的大小';

  @override
  String modelsTooLargeBody(String model, String size, String budget) {
    return '$model 加载约需 $size 内存，而本设备可为模型提供约 $budget。\n\n可以下载，但很可能无法加载或导致应用关闭。同一模型的较小版本通常也能良好运行。';
  }

  @override
  String get modelsDownloadAnyway => '仍要下载';

  @override
  String get modelsTooLargeInline => '超出本设备可加载的大小';

  @override
  String get settingsExperimentalSection => '更多功能';

  @override
  String get settingsExperimentalTitle => '显示高级功能';

  @override
  String get settingsExperimentalSubtitle =>
      '增加转写对比、字幕浮层、语音烘焙、音频编辑、本地 API 服务器，以及日志和存储查看器。';

  @override
  String get advancedAllOptions => '全部选项';

  @override
  String get advancedAllOptionsTooltip =>
      '专家选项：Whisper 专用解码开关、字幕断行、语法约束以及 CPU/GPU 调优。通常无需改动。';

  @override
  String get onboardingTitle => '设置 CrisperWeaver';

  @override
  String get onboardingSkip => '稍后设置';

  @override
  String get onboardingSetUp => '下载并继续';

  @override
  String get onboardingContinue => '继续';

  @override
  String get onboardingTaskTitle => '你想做什么？';

  @override
  String get onboardingTaskSubtitle => '我们会配置一个合适的起点。';

  @override
  String get onboardingTaskTranscribe => '转录文件';

  @override
  String get onboardingTaskTranscribeHelp => '将录音转换为可编辑文本。';

  @override
  String get onboardingTaskMeeting => '录制会议';

  @override
  String get onboardingTaskMeetingHelp => '录制语音，并在可能时区分说话人。';

  @override
  String get onboardingTaskTranslate => '翻译文本';

  @override
  String get onboardingTaskTranslateHelp => '在支持的语言之间离线翻译。';

  @override
  String get onboardingTaskSynthesize => '生成语音';

  @override
  String get onboardingTaskSynthesizeHelp => '在本地将文字生成语音。';

  @override
  String get onboardingLanguageTitle => '语言和偏好';

  @override
  String get onboardingLanguageSubtitle => '这些选择用于确定入门模型。';

  @override
  String get onboardingLanguageLabel => '主要语言';

  @override
  String get onboardingPriorityLabel => '优化目标';

  @override
  String get onboardingPriorityBalanced => '均衡';

  @override
  String get onboardingPrioritySpeed => '速度';

  @override
  String get onboardingPriorityQuality => '质量';

  @override
  String get onboardingPriorityStorage => '体积小';

  @override
  String get onboardingRecommendationTitle => '你的起始配置';

  @override
  String get onboardingRecommendationSubtitle => '之后可随时更改所有选择。';

  @override
  String get onboardingChooseModelTitle => '为此语言选择模型';

  @override
  String get onboardingChooseModelBody => '此组合没有通用的小型入门模型。我们将打开兼容模型列表，不会自动下载。';

  @override
  String onboardingRecommendedSemantics(String model, String size) {
    return '推荐模型：$model，下载大小 $size';
  }

  @override
  String get onboardingPreparing => '正在准备模型下载…';

  @override
  String onboardingFailed(String error) {
    return '设置无法完成：$error';
  }

  @override
  String modelsBestFor(String useCase) {
    return '最适合：$useCase';
  }

  @override
  String get modelsFitsDevice => '适合此设备';

  @override
  String get modelsMemoryTight => '内存可能较紧张';

  @override
  String get modelsUseMultilingual => '多语言转录';

  @override
  String get modelsUseFastTranscription => '快速转录';

  @override
  String get modelsUseTranscription => '转录';

  @override
  String get modelsUseSpeech => '语音生成';

  @override
  String get modelsUseTranslation => '离线翻译';

  @override
  String get modelsUseCleanup => '清理和摘要';

  @override
  String get modelsUseVoice => '合成语音';

  @override
  String get modelsUseAdvanced => '高级配套组件';

  @override
  String get storageLocation => '模型位置';

  @override
  String get settingsModelsDirAccessLost => '已失去对保存文件夹的访问权限。请重新选择以恢复访问。';

  @override
  String get storageFreeUnknown => '无法确定可用空间。';

  @override
  String storageFreeAvailable(String size) {
    return '此卷剩余 $size';
  }

  @override
  String get storageLowSpaceHelp => '此卷空间不足。下载其他模型前，请选择更大磁盘上的文件夹。';

  @override
  String get storageChangeLocation => '更改模型位置';

  @override
  String get storagePickDestination => '选择新的模型库文件夹';

  @override
  String get storageMoveTitle => '移动模型库？';

  @override
  String storageMoveExplanation(String path) {
    return '模型将复制并验证到 $path。新下载将使用该位置。旧副本会保留，直到你选择将其删除。';
  }

  @override
  String get storageMoveConfirm => '复制并切换';

  @override
  String storageMoving(int percent) {
    return '正在移动… $percent%';
  }

  @override
  String get storageMoveCompleteTitle => '模型库已移动';

  @override
  String storageMoveComplete(int count, String size, String path) {
    return '已在 $path 验证 $count 个文件（$size）。现在删除已验证的旧副本吗？';
  }

  @override
  String get storageKeepOldCopy => '保留旧副本';

  @override
  String get storageRemoveOldCopy => '删除旧副本';

  @override
  String storageOldCopyRemoved(String size) {
    return '已从旧位置删除 $size。';
  }

  @override
  String storageMoveFailed(String error) {
    return '无法移动模型库：$error';
  }

  @override
  String get aboutBundledEngines => '捆绑引擎';

  @override
  String get aboutReviewDiagnostics => '查看诊断报告';

  @override
  String get aboutDiagnosticsTitle => '诊断信息 — 分享前请检查';

  @override
  String get workspaceTitle => '转录工作区';

  @override
  String get workspaceOpen => '打开工作区';

  @override
  String get workspaceMissing => '找不到此转录。';

  @override
  String get workspaceExport => '导出转录';

  @override
  String get workspaceDetails => '详细信息';

  @override
  String get workspaceTranscript => '转录';

  @override
  String get workspaceCreated => '创建时间';

  @override
  String get workspaceEngine => '引擎';

  @override
  String get workspaceModel => '模型';

  @override
  String get workspaceLanguage => '语言';

  @override
  String get workspaceDuration => '时长';

  @override
  String get workspaceSegments => '片段';

  @override
  String get workspaceEditSegment => '编辑片段';

  @override
  String get workspaceRenameSpeaker => '重命名说话人';

  @override
  String get navBackToHome => '返回主页';

  @override
  String workspaceSegmentSemantics(int number, String time, String text) {
    return '片段 $number，时间 $time：$text';
  }
}
