import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera that closes as soon as it sees a Heat-Bits pairing code.
/// Returns the code's text, or null if the person backs out.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v == null) continue;
      if (v.startsWith('heatbits://')) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
      setState(() => _hint =
          "That's not a Heat-Bits code. Use the one in Settings on your PC.");
    }
  }

  /// The scanner's own error screen says only "An unexpected error occurred" in
  /// release builds, whatever went wrong. Say what it was and what to do instead.
  Widget _error(BuildContext context, MobileScannerException error) {
    final String text;
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        text = "Heat-Bits isn't allowed to use the camera.\n\n"
            'On your phone open Settings → Apps → Heat-Bits → Permissions → Camera and choose Allow, '
            'then come back and tap Scan QR code again.';
      case MobileScannerErrorCode.unsupported:
        text = "This phone doesn't have a camera Heat-Bits can use.";
      default:
        final d = error.errorDetails;
        text =
            "The camera didn't start. If another app is using it, close that app and try again.\n\n"
            '(${[d?.code, d?.message].whereType<String>().join(': ')})';
    }
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Type the code instead'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan the code on your PC'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<MobileScannerState>(
        valueListenable: _controller,
        builder: (context, scanner, _) => Stack(
          children: [
            MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: _error),
            if (scanner.error == null) ...[
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 40,
                child: Text(
                  _hint ?? 'On your PC: Heat-Bits → Settings → Devices & sync',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
