import 'package:cloud_functions/cloud_functions.dart';

class TwilioService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<bool> sendOTP(String phoneNumber) async {
    try {
      print('📤 Sending Twilio OTP to: $phoneNumber');
      final result = await _functions
          .httpsCallable('sendOTP')
          .call({'phoneNumber': phoneNumber});
      print('✅ Twilio OTP sent: ${result.data}');
      return result.data['success'] == true;
    } on FirebaseFunctionsException catch (e) {
      print('❌ Twilio sendOTP error: ${e.code} - ${e.message}');
      throw 'Failed to send OTP: ${e.message}';
    } catch (e) {
      print('💥 Unexpected error: $e');
      throw 'Failed to send OTP. Check your connection.';
    }
  }

  Future<bool> verifyOTP(String phoneNumber, String code) async {
    try {
      print('🔍 Verifying OTP for: $phoneNumber');
      final result = await _functions
          .httpsCallable('verifyOTP')
          .call({'phoneNumber': phoneNumber, 'code': code});
      print('✅ Verify result: ${result.data}');
      return result.data['success'] == true;
    } on FirebaseFunctionsException catch (e) {
      print('❌ Twilio verifyOTP error: ${e.code} - ${e.message}');
      throw 'Invalid OTP code. Try again.';
    } catch (e) {
      print('💥 Unexpected error: $e');
      throw 'Verification failed. Check your connection.';
    }
  }
}