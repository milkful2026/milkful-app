import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/my_orders_bloc.dart';
import '../../bloc/my_orders_event.dart';

/// Opens an order or scheduled-delivery detail from My Orders. A detail
/// screen closes with `true` after a change (MA-155: a cancel), and My
/// Orders then reloads, so the list shows the new status or drops the
/// cancelled delivery. A plain back costs no request.
Future<void> openOrderDetail(BuildContext context, String location, {Object? extra}) async {
  final bloc = context.read<MyOrdersBloc>();
  final changed = await context.push<bool>(location, extra: extra);
  if (changed == true && !bloc.isClosed) bloc.add(MyOrdersRefreshed());
}
