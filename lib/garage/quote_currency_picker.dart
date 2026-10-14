import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'garage_currencies.dart';

/// Drop-in currency selector for a future workshop quote editor.
///
/// Preferred region currencies are displayed first, followed by other ISO
/// codes. A published work order keeps its original quote currency across
/// revisions; its server API rejects subsequent changes.
class GarageQuoteCurrencyPicker extends StatelessWidget {
  const GarageQuoteCurrencyPicker({
    required this.currency,
    required this.onChanged,
    super.key,
  });

  final String currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    GarageCurrencies.digits(currency);
    final polish = AppLocale.language.value == 'pl';
    return DropdownButtonFormField<String>(
      key: const Key('garage_quote_currency'),
      initialValue: currency,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: polish ? 'Waluta kosztorysu' : 'Estimate currency',
        helperText: polish
            ? 'Kwota będzie zapisana w wybranej walucie.'
            : 'Amounts are recorded in the selected currency.',
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final code in [
          ...GarageCurrencies.preferred,
          ...GarageCurrencies.others,
        ])
          DropdownMenuItem<String>(
            value: code,
            child: Text(
              code,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null && value != currency) {
          onChanged(value);
        }
      },
    );
  }
}
