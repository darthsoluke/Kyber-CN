import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mason_logger/mason_logger.dart';

const _licenseFilePath =
    '~/.local/share/maxima/wine/prefix/drive_c/ProgramData/Electronic Arts/EA Services/License/1035052.dlf';

final class DedicatedServerLicenseException implements Exception {
  const DedicatedServerLicenseException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerLicenseConfig {
  const DedicatedServerLicenseConfig._({
    required this.enabled,
    required this.endpoint,
    required this.authToken,
    required this.pinnedProxyId,
  });

  factory DedicatedServerLicenseConfig.fromEnvironment(
    Map<String, String> environment,
  ) {
    final endpoint = environment['KYBER_LICENSE_ENDPOINT'];
    final authToken = environment['KYBER_LICENSE_AUTH_TOKEN'];

    if (_isEmpty(endpoint) && _isEmpty(authToken)) {
      return DedicatedServerLicenseConfig._(
        enabled: false,
        endpoint: '',
        authToken: '',
        pinnedProxyId: _parsePinnedProxyId(
          environment['KYBER_SERVER_METADATA'],
        ),
      );
    }

    if (_isEmpty(endpoint) || _isEmpty(authToken)) {
      throw const DedicatedServerLicenseException(
        'KYBER_LICENSE_ENDPOINT and KYBER_LICENSE_AUTH_TOKEN must be set '
        'together.',
      );
    }

    return DedicatedServerLicenseConfig._(
      enabled: true,
      endpoint: endpoint!.trim(),
      authToken: authToken!.trim(),
      pinnedProxyId: _parsePinnedProxyId(environment['KYBER_SERVER_METADATA']),
    );
  }

  final bool enabled;
  final String endpoint;
  final String authToken;
  final String pinnedProxyId;

  static bool _isEmpty(String? value) => value == null || value.trim().isEmpty;

  static String _parsePinnedProxyId(String? metadata) {
    if (_isEmpty(metadata)) {
      return '';
    }

    final entries = metadata!.split(',').map((item) {
      final split = item.split('=');
      if (split.length != 2 ||
          split.first.trim().isEmpty ||
          split.last.trim().isEmpty) {
        throw DedicatedServerLicenseException(
          'Invalid KYBER_SERVER_METADATA entry: $item',
        );
      }

      return MapEntry(split.first.trim(), split.last.trim());
    });

    final map = Map<String, String>.fromEntries(entries);
    return map['pinned_proxy_id'] ?? '';
  }
}

final class DedicatedServerLicenseService {
  DedicatedServerLicenseService({
    required this.config,
    required Logger logger,
    Dio? dio,
  }) : _logger = logger,
       _dio = dio ?? Dio() {
    if (config.enabled) {
      _dio.options.headers['Authorization'] = 'Bearer ${config.authToken}';
    }
  }

  final DedicatedServerLicenseConfig config;
  final Logger _logger;
  final Dio _dio;

  Future<String?> fetch({
    required String id,
    bool writeLicenseFile = false,
  }) async {
    if (!config.enabled) {
      _logger.info(
        'License sync disabled: KYBER_LICENSE_ENDPOINT and '
        'KYBER_LICENSE_AUTH_TOKEN are not set.',
      );
      return null;
    }

    _logger.info('Fetching license from ${config.endpoint}');

    try {
      final response = await _dio.get<List<int>>(
        '${config.endpoint}/$id${_regionQuery()}',
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 404) {
        _logger.info('License not found on server');
        return null;
      }

      if (response.statusCode != 200) {
        throw DedicatedServerLicenseException(
          'Failed to fetch license: '
          '${response.statusCode} ${response.statusMessage}',
        );
      }

      final licenseData = response.data;
      if (licenseData == null) {
        throw const DedicatedServerLicenseException(
          'License server returned an empty response body.',
        );
      }

      if (!writeLicenseFile) {
        _logger.success('License fetched successfully');
        return utf8.decode(licenseData);
      }

      _resolveLicenseFile()
        ..createSync(recursive: true)
        ..writeAsBytesSync(licenseData);
      _logger.success('License fetched and saved to $_licenseFilePath');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.info('License not found on server');
        return null;
      }

      throw DedicatedServerLicenseException(
        'Error fetching license: ${e.message}',
      );
    }
  }

  Future<void> upload({required String id, String? data}) async {
    if (!config.enabled) {
      _logger.info(
        'License upload disabled: KYBER_LICENSE_ENDPOINT and '
        'KYBER_LICENSE_AUTH_TOKEN are not set.',
      );
      return;
    }

    _logger.info('Uploading Denuvo token to license server...');
    final licenseData = _resolveUploadData(data);

    final response = await _dio.put<void>(
      '${config.endpoint}/$id${_regionQuery()}',
      data: licenseData,
      options: Options(
        headers: {
          Headers.contentTypeHeader: 'application/octet-stream',
          Headers.contentLengthHeader: licenseData.length,
        },
      ),
    );

    if (response.statusCode != 200) {
      throw DedicatedServerLicenseException(
        'Failed to upload license: '
        '${response.statusCode} ${response.statusMessage}',
      );
    }

    _logger.success('License uploaded successfully');
  }

  List<int> _resolveUploadData(String? data) {
    if (data != null && data.isNotEmpty) {
      return utf8.encode(data);
    }

    if (!Platform.isLinux) {
      throw const DedicatedServerLicenseException(
        'License upload requires token data on non-Linux hosts.',
      );
    }

    final licenseFile = _resolveLicenseFile();
    if (!licenseFile.existsSync()) {
      throw const DedicatedServerLicenseException(
        'License file not found at $_licenseFilePath',
      );
    }

    return licenseFile.readAsBytesSync();
  }

  File _resolveLicenseFile() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const DedicatedServerLicenseException(
        'HOME is required to resolve the Maxima license file path.',
      );
    }

    return File(_licenseFilePath.replaceFirst('~', home));
  }

  String _regionQuery() {
    if (config.pinnedProxyId.isEmpty) {
      return '';
    }

    return '?region=${Uri.encodeQueryComponent(config.pinnedProxyId)}';
  }
}
