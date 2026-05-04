import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/constants.dart';
import '../utils/localization_helpers.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;

  const OtpVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _digitControllers;
  late final List<FocusNode> _digitFocusNodes;
  Timer? _resendTimer;
  int _secondsUntilResend = 30;
  String? _otpError;

  String get _otp =>
      _digitControllers.map((controller) => controller.text).join();

  bool get _canVerify => _otp.length == 6;

  @override
  void initState() {
    super.initState();
    _digitControllers = List.generate(6, (_) => TextEditingController());
    _digitFocusNodes = List.generate(6, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _digitFocusNodes.first.requestFocus();
      }
    });
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in _digitControllers) {
      controller.dispose();
    }
    for (final focusNode in _digitFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _secondsUntilResend = 30;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsUntilResend <= 1) {
        timer.cancel();
        setState(() {
          _secondsUntilResend = 0;
        });
        return;
      }

      setState(() {
        _secondsUntilResend -= 1;
      });
    });
  }

  void _handleDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '').split('');
      for (var i = 0; i < _digitControllers.length; i++) {
        _digitControllers[i].text = i < digits.length ? digits[i] : '';
      }
      final nextIndex = digits.length >= 6 ? 5 : digits.length;
      _digitFocusNodes[nextIndex].requestFocus();
    } else if (value.isNotEmpty && index < _digitFocusNodes.length - 1) {
      _digitFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _digitFocusNodes[index - 1].requestFocus();
    }

    setState(() {
      _otpError = null;
    });
  }

  Future<void> _resendOtp() async {
    final l10n = context.l10n;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.resendSignupOtp(widget.email);

    if (!mounted) return;

    if (success) {
      for (final controller in _digitControllers) {
        controller.clear();
      }
      _digitFocusNodes.first.requestFocus();
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.otpSentToEmail),
          backgroundColor: AppColors.successColor,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error != null
                ? localizeRawMessage(l10n, authProvider.error!)
                : 'Unable to resend OTP',
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    if (_otp.length != 6) {
      setState(() {
        _otpError = l10n.otpMustBeSixDigits;
      });
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifySignupOtp(
      email: widget.email,
      otp: _otp,
    );

    if (success && mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        authProvider.isAdmin ? '/admin-dashboard' : '/home',
        (route) => false,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error != null
                ? localizeRawMessage(l10n, authProvider.error!)
                : 'OTP verification failed',
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Widget _buildOtpBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_digitControllers.length, (index) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.backspace &&
                _digitControllers[index].text.isEmpty &&
                index > 0) {
              _digitFocusNodes[index - 1].requestFocus();
              _digitControllers[index - 1].clear();
              setState(() {
                _otpError = null;
              });
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            width: 45,
            child: TextFormField(
              controller: _digitControllers[index],
              focusNode: _digitFocusNodes[index],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.primaryColor,
                    width: 2,
                  ),
                ),
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              onChanged: (value) => _handleDigitChanged(index, value),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify email'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.primaryColor,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 76,
                          color: AppColors.primaryColor,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Enter verification code',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.otpSentToEmail}\n${widget.email}',
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        _buildOtpBoxes(),
                        if (_otpError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _otpError!,
                            style: const TextStyle(color: AppColors.errorColor),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: authProvider.isLoading || !_canVerify
                              ? null
                              : _verifyOtp,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: authProvider.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Verify',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed:
                              authProvider.isLoading || _secondsUntilResend > 0
                                  ? null
                                  : _resendOtp,
                          child: Text(
                            _secondsUntilResend > 0
                                ? 'Wait ${_secondsUntilResend}s'
                                : 'Resend OTP',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
