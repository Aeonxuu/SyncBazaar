import 'package:flutter_bloc/flutter_bloc.dart';

class PostBazaarCubit extends Cubit<int> {
  PostBazaarCubit() : super(0);

  void selectTab(int index) => emit(index);
}
