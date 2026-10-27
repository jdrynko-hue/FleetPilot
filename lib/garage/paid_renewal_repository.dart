import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';

class GaragePaidRenewalStatus {
 const GaragePaidRenewalStatus({required this.stopping,required this.endsAt});
 final bool stopping;
 final DateTime endsAt;
 static GaragePaidRenewalStatus parse(Object? raw) {
  if(raw is! Map||raw.length!=2||!raw.containsKey('status')||!raw.containsKey('access_ends_at')||
   !{'renewing','stopping'}.contains(raw['status'])||raw['access_ends_at'] is! String) {
   throw const FormatException('Invalid renewal status');
  }
  final at=DateTime.tryParse(raw['access_ends_at'] as String);
  if(at==null||!at.isUtc)throw const FormatException('Invalid renewal time');
  return GaragePaidRenewalStatus(stopping:raw['status']=='stopping',endsAt:at);
 }
}

class GaragePaidRenewalRepository {
 GaragePaidRenewalRepository({required this.enabled,required this.supabaseUrl,
 required this.currentUserId,required this.currentSessionKey,required this.invoke,
 this.timeout=const Duration(seconds:20)});
 factory GaragePaidRenewalRepository.forClient(SupabaseClient client)=>GaragePaidRenewalRepository(
  enabled:AppConfig.garagePaidRenewalEnabled,supabaseUrl:AppConfig.supabaseUrl,
  currentUserId:()=>client.auth.currentUser?.id,currentSessionKey:()=>client.auth.currentSession?.accessToken,
  invoke:(body)async=>(await client.functions.invoke('flotaryx-garage-test-paid-renewal',body:body)).data);
 final bool enabled;
 final String supabaseUrl;
 final String? Function() currentUserId,currentSessionKey;
 final Future<Object?> Function(Map<String,Object>) invoke;
 final Duration timeout;
 static final _uuid=RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
 bool available(String workspace)=>enabled&&AppConfig.isEcosystemQaBackend(supabaseUrl)&&
  _uuid.hasMatch(workspace)&&_uuid.hasMatch(currentUserId()??'')&&(currentSessionKey()?.isNotEmpty??false)&&
  timeout>Duration.zero&&timeout<=const Duration(seconds:30);
 Future<GaragePaidRenewalStatus?> request(String workspace,{bool stop=false}) async {
  if(!available(workspace))return null;
  final actor=currentUserId(),session=currentSessionKey();
  try {
   final raw=await invoke(Map<String,Object>.unmodifiable({'workspace_id':workspace,'action':stop?'stop':'status'})).timeout(timeout);
   if(currentUserId()!=actor||currentSessionKey()!=session||!available(workspace))return null;
   final result=GaragePaidRenewalStatus.parse(raw);
   if(!result.endsAt.isAfter(DateTime.now().toUtc())||(stop&&!result.stopping))return null;
   return result;
  }catch(_){return null;}
 }
}
