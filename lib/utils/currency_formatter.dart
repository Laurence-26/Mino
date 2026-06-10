import 'package:intl/intl.dart';

String formatCurrency(double amount) {
  final format = NumberFormat.currency(locale: 'en_US', symbol: r'');
  return format.format(amount);
}