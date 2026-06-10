import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pesa_tools/110n/app_translations.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _storage = const FlutterSecureStorage();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isConfirmStep = false;
  String _firstPin = '';
  bool _isLoading = false;

  Future<void> _savePin(String pin) async {
    setState(() => _isLoading = true);
    try {
      await _storage.write(key: 'app_pin', value: pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ App PIN set successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving PIN: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isConfirmStep ? 'Confirm PIN' : 'Set App PIN'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 90, color: theme.primaryColor),
            const SizedBox(height: 40),
            Text(
              _isConfirmStep
                  ? 'Re-enter your 4-digit PIN'
                  : 'Create a 4-digit PIN for local protection',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            TextField(
              controller: _isConfirmStep ? _confirmController : _pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 42, letterSpacing: 30),
              decoration: InputDecoration(
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                hintText: '••••',
              ),
              onChanged: (value) {
                if (value.length == 4) {
                  if (!_isConfirmStep) {
                    setState(() {
                      _firstPin = value;
                      _isConfirmStep = true;
                    });
                    _confirmController.clear();
                  } else {
                    if (value == _firstPin) {
                      _savePin(value);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PINs do not match')),
                      );
                      setState(() {
                        _isConfirmStep = false;
                        _pinController.clear();
                        _confirmController.clear();
                      });
                    }
                  }
                }
              },
            ),
            if (_isConfirmStep)
              TextButton(
                onPressed: () {
                  setState(() {
                    _isConfirmStep = false;
                    _confirmController.clear();
                  });
                },
                child: const Text('Go Back'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }
}