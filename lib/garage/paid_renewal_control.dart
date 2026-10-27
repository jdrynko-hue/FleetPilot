import 'package:flutter/material.dart';
import 'paid_renewal_repository.dart';
import 'paid_renewal_text.dart';
class GaragePaidRenewalControl extends StatefulWidget {
 const GaragePaidRenewalControl({required this.repository,required this.workspaceId,required this.canManage,super.key});
 final GaragePaidRenewalRepository repository;
 final String workspaceId;
 final bool Function() canManage;
 @override
 State<GaragePaidRenewalControl> createState()=>_PaidRenewalState();
}
class _PaidRenewalState extends State<GaragePaidRenewalControl> {
 GaragePaidRenewalStatus? _status;
 bool _busy=true,_attempted=false,_error=false;
 int _generation=0;
 bool get _available=>widget.canManage()&&widget.repository.available(widget.workspaceId);
 @override
 void initState(){super.initState();_request(false);}
 @override
 void didUpdateWidget(covariant GaragePaidRenewalControl old){
  super.didUpdateWidget(old);
  if(old.repository!=widget.repository||old.workspaceId!=widget.workspaceId){
   ++_generation;_status=null;_error=false;_busy=true;_request(false);
  }
 }
 @override
 void dispose(){++_generation;super.dispose();}
 Future<void> _request(bool stop)async{
  final generation=++_generation,repository=widget.repository,workspace=widget.workspaceId;
  final actor=repository.currentUserId(),session=repository.currentSessionKey();
  final result=_available?await repository.request(workspace,stop:stop):null;
  if(!mounted||generation!=_generation)return;
  final valid=identical(repository,widget.repository)&&workspace==widget.workspaceId&&
   repository.currentUserId()==actor&&repository.currentSessionKey()==session&&_available;
  setState((){_busy=false;_status=valid?result:null;_error=!valid||result==null;});
 }
 Future<void> _stop()async{
  if(_busy||_attempted||_status==null||_status!.stopping||!_available)return;
  final repository=widget.repository,workspace=widget.workspaceId,generation=_generation;
  final actor=repository.currentUserId(),session=repository.currentSessionKey();
  setState(()=>_busy=true);
  final confirmed=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
   title:Text(GaragePaidRenewalText.get(0)),content:Text(GaragePaidRenewalText.get(1)),
   actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(GaragePaidRenewalText.get(2))),
    FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(GaragePaidRenewalText.get(3)))]));
  if(!mounted)return;
  if(generation!=_generation||repository!=widget.repository||workspace!=widget.workspaceId||
   actor!=repository.currentUserId()||session!=repository.currentSessionKey()||!_available){
   setState((){_busy=false;_status=null;_error=true;});return;
  }
  if(confirmed!=true){setState(()=>_busy=false);return;}
  _attempted=true;await _request(true);
 }
 @override
 Widget build(BuildContext context){
  final t=GaragePaidRenewalText.get;
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   if(_busy)Text(t(7))
   else if(_error)Text(t(5))
   else if(_status?.stopping==true)Text(t(4).replaceFirst('{date}',_status!.endsAt.toIso8601String().replaceFirst('T',' ').substring(0,16)+' UTC'))
   else OutlinedButton(onPressed:_available&&!_attempted?_stop:null,child:Text(t(0))),
   TextButton(onPressed:_busy?null:(){setState(()=>_busy=true);_request(false);},child:Text(t(6))),
  ]);
 }
}
