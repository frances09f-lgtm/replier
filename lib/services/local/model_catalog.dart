/// Pinned community quantizations of Apache-2.0 Qwen weights.
/// Model files stay outside the APK; SHA-256 is verified before use.
class LocalModelSpec {
  const LocalModelSpec(
    this.id,
    this.label,
    this.repo,
    this.revision,
    this.fileName,
    this.bytes,
    this.sha256,
  );
  final String id, label, repo, revision, fileName, sha256;
  final int bytes;
  Uri get url =>
      Uri.https('huggingface.co', '/$repo/resolve/$revision/$fileName');
  static const primary = LocalModelSpec(
    'qwen35_2b',
    'Qwen3.5 2B · Q4_K_M',
    'bartowski/Qwen_Qwen3.5-2B-GGUF',
    '7d26695454df6de5fbcce2e58681e62dae06ce43',
    'Qwen_Qwen3.5-2B-Q4_K_M.gguf',
    1396198496,
    '57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8',
  );
  static const alternate = LocalModelSpec(
    'qwen3_17b',
    'Qwen3 1.7B · Q4_K_M',
    'bartowski/Qwen_Qwen3-1.7B-GGUF',
    'dcb19155b962dbb6389f4691a982043a8e651022',
    'Qwen_Qwen3-1.7B-Q4_K_M.gguf',
    1282439584,
    '72c5c3cb38fa32d5256e2fe30d03e7a64c6c79e668ad84057e3bd66e250b24fb',
  );
  static const light = LocalModelSpec(
    'qwen3_06b',
    'Qwen3 0.6B · Q4_K_M · lighter CPU option',
    'bartowski/Qwen_Qwen3-0.6B-GGUF',
    '60b85c0e3d8fe0f6474f406922a26d12aca4550d',
    'Qwen_Qwen3-0.6B-Q4_K_M.gguf',
    484220320,
    '9acfc1e001311f34b4252001b626f2e466d592a42065f66571bff3790d4e1b14',
  );
  static const all = [light, primary, alternate];
}
