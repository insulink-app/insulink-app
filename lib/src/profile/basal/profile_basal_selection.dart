import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/basal/basal_bar_chart.dart';
import 'package:insulink/src/profile/basal/basal_editor.dart';
import 'package:insulink/src/profile/basal/profile_basal_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Lists the user's basal-rate profiles: each is a card with a radio to make it
/// the active profile, its name + daily total, and a preview of its curve.
/// Tapping a card opens the [BasalEditor]; the button below adds a new profile.
class ProfileBasalSelection extends StatelessWidget {
  const ProfileBasalSelection({super.key});

  void _open(BuildContext context, int index) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => BasalEditor(index: index)));
  }

  void _add(BuildContext context) {
    final state = context.read<ProfileBasalState>();
    final controller = TextEditingController();
    Alert(
      icon: PhosphorIconsRegular.plus,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocaleText(
            'profile.basal.new_title',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: Locales.string(context, 'profile.basal.name'),
            ),
          ),
        ],
      ),
      cancelButton: true,
      confirmButtonText: 'alert.done',
      callback: () {
        final name = controller.text.trim();
        if (name.isNotEmpty) {
          _open(context, state.addProfile(name));
        }
      },
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileBasalState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < state.profiles.length; index++) ...[
          _ProfileCard(index: index),
          const SizedBox(height: 12),
        ],
        _AddProfileButton(onTap: () => _add(context)),
      ],
    );
  }
}

/// A dashed, accent-tinted "add" tile that reads as a placeholder for the next
/// profile rather than a plain button.
class _AddProfileButton extends StatelessWidget {
  const _AddProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsRegular.plus, size: 20, color: accent),
              const SizedBox(width: 8),
              LocaleText(
                'profile.basal.add_profile',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.index});

  final int index;

  void _confirmDelete(BuildContext context) {
    final state = context.read<ProfileBasalState>();
    Alert(
      type: AlertType.error,
      icon: PhosphorIconsRegular.trash,
      description: 'profile.basal.delete_title',
      cancelButton: true,
      confirmButtonText: 'alert.delete',
      confirmButtonColor: Colors.red,
      callback: () => state.deleteProfile(index),
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileBasalState>();
    final profile = state.profiles[index];
    final theme = Theme.of(context);
    final active = index == state.activeIndex;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => BasalEditor(index: index)),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? theme.colorScheme.primary : theme.dividerColor,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      active
                          ? PhosphorIconsFill.circle
                          : PhosphorIconsRegular.circle,
                      color: active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    onPressed: () => state.selectActive(index),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Locales.string(
                            context,
                            'profile.basal.total',
                            params: [profile.total.toStringAsFixed(2)],
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.profiles.length > 1)
                    IconButton(
                      icon: const Icon(PhosphorIconsRegular.trash),
                      onPressed: () => _confirmDelete(context),
                    ),
                  Icon(
                    PhosphorIconsRegular.caretRight,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: BasalBarChart(rates: profile.rates, height: 70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
