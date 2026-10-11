// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:replier/repositories/log_repository.dart' as _i257;
import 'package:replier/repositories/rule_repository.dart' as _i722;
import 'package:replier/repositories/settings_repository.dart' as _i912;
import 'package:replier/repositories/statistics_repository.dart' as _i752;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    gh.factory<_i257.LogRepository>(() => _i257.LogRepository());
    gh.factory<_i722.RuleRepository>(() => _i722.RuleRepository());
    gh.factory<_i912.SettingsRepository>(() => _i912.SettingsRepository());
    gh.factory<_i752.StatisticsRepository>(() => _i752.StatisticsRepository(
          gh<_i912.SettingsRepository>(),
          gh<_i722.RuleRepository>(),
          gh<_i257.LogRepository>(),
        ));
    return this;
  }
}
