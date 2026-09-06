import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/nutrition/food/food_editor_sheet.dart';
import 'package:insulink/src/nutrition/food/food_product.dart';
import 'package:insulink/src/nutrition/food/off_client.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Full-text search of the public Open Food Facts database. Typing runs a
/// debounced query; tapping a result opens the editor pre-filled so the user can
/// complete/adjust fields before it is saved into their product list.
class FoodSearchPage extends StatefulWidget {
  const FoodSearchPage({super.key});

  @override
  State<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends State<FoodSearchPage> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<FoodProduct> _results = const [];
  bool _loading = false;

  /// Rises with each query so a slow earlier response can't overwrite a newer
  /// one's results.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _run(value.trim()),
    );
  }

  Future<void> _run(String terms) async {
    final id = ++_requestId;
    final results = await const OffClient().search(terms);
    if (!mounted || id != _requestId) {
      return;
    }
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  /// Opens the editor on a search hit and closes the page, reporting whatever
  /// the editor saved so a picker can take it straight to the portion.
  Future<void> _pick(FoodProduct product) async {
    final saved = await showFoodEditor(context, product: product);
    if (mounted) {
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: Locales.string(context, 'nutrition.food.search_hint'),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(PhosphorIconsBold.x),
                    onPressed: () {
                      _query.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.text.trim().length < 2) {
      return _hint('nutrition.food.search_start');
    }
    if (_results.isEmpty) {
      return _hint('nutrition.food.search_none');
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) => _tile(_results[index]),
    );
  }

  Widget _tile(FoodProduct product) {
    final scheme = Theme.of(context).colorScheme;
    final subtitleParts = [
      if (product.brand.isNotEmpty) product.brand,
      Locales.string(
        context,
        'injection.products.carbs_per_100',
        params: [product.carbs100g.toStringAsFixed(0)],
      ),
    ];
    return ListTile(
      leading: Icon(
        product.unit == 'ml'
            ? PhosphorIconsBold.drop
            : PhosphorIconsBold.forkKnife,
        color: scheme.primary,
      ),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _pick(product),
    );
  }

  Widget _hint(String key) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: LocaleText(
          key,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
