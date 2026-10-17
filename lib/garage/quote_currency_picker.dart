import 'package:flutter/material.dart';

import 'garage_ui_text.dart';
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
    this.enabled = true,
    super.key,
  });

  final String currency;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    GarageCurrencies.digits(currency);
    return DropdownButtonFormField<String>(
      key: const Key('garage_quote_currency'),
      initialValue: currency,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: GarageUiText.get('estimateCurrency'),
        helperText: GarageUiText.get('estimateCurrencyHint'),
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
      onChanged: !enabled ? null : (value) {
        if (enabled && value != null && value != currency) {
          onChanged(value);
        }
      },
    );
  }
}
