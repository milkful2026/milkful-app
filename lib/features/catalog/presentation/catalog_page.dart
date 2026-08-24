import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/catalog_bloc.dart';
import '../bloc/catalog_event.dart';
import 'catalog_screen.dart';
import 'widgets/promo_banner.dart';

/// Full browse/search/filter/sort destination — reached from Home's landing
/// page via "View All" (Categories) and its search bar, both of which just
/// navigate here rather than duplicating [CatalogScreen]'s own category
/// rail/filter/sort chrome inline on the landing page. Owns its own
/// [CatalogBloc] instance (mirrors Home's previous scoping) and the search
/// field that used to live in Home's AppBar — [CatalogScreen] itself has
/// never rendered a search field of its own. Starts with the "All" pill
/// selected (`showAllByDefault`) rather than one arbitrary category, since
/// a "View All" tap should actually show everything.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, CatalogBloc bloc) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      bloc.add(SearchQueryChanged(query));
    });
  }

  void _onSearchCleared(CatalogBloc bloc) {
    _searchDebounce?.cancel();
    _searchController.clear();
    bloc.add(const SearchCleared());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          CatalogBloc(repository: context.read())..add(const CatalogStarted(showAllByDefault: true)),
      child: Builder(
        builder: (context) {
          final bloc = context.read<CatalogBloc>();
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              titleSpacing: 0,
              title: Semantics(
                label: 'Search products',
                child: TextField(
                  key: const Key('catalog-search-field'),
                  controller: _searchController,
                  onChanged: (query) => _onSearchChanged(query, bloc),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search for "Milk"',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _onSearchCleared(bloc)),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            body: Column(
              children: [
                // Search field lives in the AppBar above; the category rail
                // (round icons) is CatalogScreen's own first child below —
                // this sits between the two, same ordering as Home's
                // landing page.
                PromoBanner(onShopNow: () => bloc.add(const AllProductsSelected())),
                const Expanded(child: CatalogScreen()),
              ],
            ),
          );
        },
      ),
    );
  }
}
