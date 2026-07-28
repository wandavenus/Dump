import 'dart:io';

class AudioConversionService {
  const AudioConversionService({AudioConversionExecutor? executor}) : _executor = executor;

  final AudioConversionExecutor? _executor;

  Future<ConversionResult> convertFile({
    required String inputPath,
    required String outputPath,
    required AudioOutputFormat format,
    int? bitrate,
    int? sampleRate,
    int? bitDepth,
  }) async {
    if (!await File(inputPath).exists()) {
      return ConversionResult.failure('Input file does not exist: $inputPath');
    }

    final executor = _executor;
    if (executor == null) {
      return ConversionResult.failure('No audio conversion executor is configured.');
    }

    return executor.convert(
      inputPath: inputPath,
      outputPath: outputPath,
      format: format,
      bitrate: bitrate,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
    );
  }

  bool needsConversion(String filePath, AudioOutputFormat targetFormat) {
    final extension = filePath.split('.').last.toLowerCase();
    return extension != targetFormat.fileExtension;
  }

  List<AudioOutputFormat> get supportedFormats => AudioOutputFormat.values;
}

abstract class AudioConversionExecutor {
  Future<ConversionResult> convert({
    required String inputPath,
    required String outputPath,
    required AudioOutputFormat format,
    int? bitrate,
    int? sampleRate,
    int? bitDepth,
  });
}

class ConversionResult {
  final bool success;
  final String? outputPath;
  final String? error;

  const ConversionResult._({required this.success, this.outputPath, this.error});

  const ConversionResult.success(String outputPath) : this._(success: true, outputPath: outputPath);

  const ConversionResult.failure(String error) : this._(success: false, error: error);
}

enum AudioOutputFormat {
  flac('flac'),
  mp3_320('mp3'),
  mp3_v0('mp3'),
  aac_256('m4a'),
  opus_128('opus'),
  alac('m4a'),
  wav('wav');

  const AudioOutputFormat(this.fileExtension);

  final String fileExtension;
}
