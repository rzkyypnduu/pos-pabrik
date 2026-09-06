import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/product.dart';

class ProductProvider extends ChangeNotifier {
  List<Product> _products = [];
  List<Product> get products => _products;

  Future<void> loadProducts() async {
    _products = await DatabaseHelper.instance.getProducts();
    notifyListeners();
  }

  Future<void> addProduct(String name, int price) async {
    await DatabaseHelper.instance.insertProduct(Product(name: name, price: price));
    await loadProducts();
  }

  Future<void> updateProductPrice(int id, int price) async {
    final product = _products.firstWhere((p) => p.id == id);
    await DatabaseHelper.instance.updateProduct(product.copyWith(price: price));
    await loadProducts();
  }

  Future<void> deleteProduct(int id) async {
    await DatabaseHelper.instance.deleteProduct(id);
    await loadProducts();
  }

  Future<void> seedProducts() async {
    await DatabaseHelper.instance.seedProducts();
    await loadProducts();
  }
}
