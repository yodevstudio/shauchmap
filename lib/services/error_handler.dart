import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../main.dart';

class AppError {
  static void show(
    BuildContext context,
    Object error, {
    String? fallback,
    VoidCallback? onRetry,
  }) {
    String message = fallback ?? "Something went wrong. Please try again.";

    if (error is SocketException) {
      message = "No connection. Please check your internet and try again.";
    } else if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          message = "You don't have permission to perform this action.";
          break;
        case 'unavailable':
          message = "Service is currently unavailable. Please try again later.";
          break;
        case 'network-request-failed':
          message = "Network connection failed. Please check your internet.";
          break;
        default:
          message =
              error.message ??
              fallback ??
              "A database error occurred. Please try again.";
      }
    } else if (error is String) {
      message = error;
    }

    showAppSnackBar(message, isError: true);
  }
}
