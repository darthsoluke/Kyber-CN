import 'dart:io';

import 'package:ffigen/ffigen.dart';

void main() {
  final packageRoot = Platform.script.resolve('../');
  final libclang =
      Platform.environment['KYBER_LIBCLANG'] ??
      r'D:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\Llvm\x64\bin\libclang.dll';

  FfiGenerator(
    enums: .includeAll,
    functions: .includeAll,
    globals: .includeAll,
    macros: .includeAll,
    typedefs: .includeAll,
    structs: .includeAll,
    unnamedEnums: .includeAll,
    unions: .includeAll,
    output: Output(
      style: const DynamicLibraryBindings(),
      dartFile: packageRoot.resolve('lib/gen/generated_bindings.dart'),
    ),
    headers: Headers(
      compilerOptions: [
        '-include',
        'stdbool.h',
        '-I${packageRoot.resolve('third_party/vivox').path.substring(1)}',
      ],
      entryPoints: [
        packageRoot.resolve(
          'third_party/vivox/ffigen_vivox_shim.h',
        ),
        packageRoot.resolve('third_party/unrar.h'),
      ],
    ),
  ).generate(
    libclangDylib: Uri.file(libclang),
  );
}
