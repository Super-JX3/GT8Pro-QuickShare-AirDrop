package local.gt8pro.moseybridge;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.os.Bundle;
import android.os.Binder;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.provider.OpenableColumns;
import java.io.*;
import java.nio.charset.StandardCharsets;
public final class FixtureProvider extends ContentProvider {
 public static final Uri URI=Uri.parse("content://local.gt8pro.moseybridge.fixture/send-test.txt");
 public static final String NAME="GT8Pro-AirDrop-082-SystemShare.txt";
 private static boolean valid(Uri uri){return URI.equals(uri);}
 static byte[] bytes(){byte[] line="GT8 Pro AirDrop 082 system share synthetic fixture. No personal data.\n".getBytes(StandardCharsets.US_ASCII);byte[] data=new byte[8192];for(int i=0;i<data.length;i++)data[i]=line[i%line.length];return data;}
 @Override public boolean onCreate(){return true;}
 @Override public String getType(Uri uri){return valid(uri)?"text/plain":null;}
 @Override public Cursor query(Uri uri,String[] projection,String selection,String[] selectionArgs,String sortOrder){
  if(!valid(uri))throw new IllegalArgumentException("Fixture URI only");
  String[] columns=projection==null?new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE}:projection;
  MatrixCursor cursor=new MatrixCursor(columns);Object[] values=new Object[columns.length];
  for(int i=0;i<columns.length;i++)values[i]=OpenableColumns.DISPLAY_NAME.equals(columns[i])?NAME:OpenableColumns.SIZE.equals(columns[i])?Long.valueOf(8192):null;
  cursor.addRow(values);return cursor;
 }
 @Override public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{
  if(!valid(uri)||!"r".equals(mode))throw new FileNotFoundException("Read-only fixture");
  try{
   ParcelFileDescriptor[] pipe=ParcelFileDescriptor.createPipe();
   Thread writer=new Thread(()->{try(OutputStream out=new ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])){out.write(bytes());}catch(IOException ignored){}},"GT8SyntheticFixture");writer.setDaemon(true);writer.start();return pipe[0];
  }catch(IOException failure){throw new FileNotFoundException("Fixture pipe unavailable");}
 }
 @Override public Bundle call(String method,String arg,Bundle extras){
  if(Binder.getCallingUid()!=0)throw new SecurityException("Root fixture control only");
  if(arg!=null||(extras!=null&&!extras.isEmpty())||!("inspect-own-fixture".equals(method)||"grant-own-fixture".equals(method)||"revoke-own-fixture".equals(method)))throw new IllegalArgumentException("Fixed fixture operation only");
  long identity=Binder.clearCallingIdentity();
  try{
   android.net.Uri active=MediaFixture.saved(getContext());
   if(active==null)active=URI;
   int targetUid;
   try{
    PackageManager pm=getContext().getPackageManager();
    targetUid=pm.getApplicationInfo("com.google.android.mosey",0).uid;
    String[] owners=pm.getPackagesForUid(targetUid);
    if(!UidPolicy.validTarget(android.os.Process.myUid(),targetUid,owners))targetUid=-1;
   }
   catch(PackageManager.NameNotFoundException unavailable){targetUid=-1;}
   Bundle result=new Bundle();
   if("inspect-own-fixture".equals(method)){
    result.putInt("fixture_source_uid",android.os.Process.myUid());
    result.putInt("fixture_target_uid",targetUid);
    result.putString("fixture_uri",active.toString());
   }else if("grant-own-fixture".equals(method)){
    boolean valid=URI.equals(active);
    try{if(!valid)valid=MediaFixture.valid(getContext(),active);}catch(Exception failure){valid=false;}
    if(targetUid>=10000&&valid)getContext().grantUriPermission("com.google.android.mosey",active,Intent.FLAG_GRANT_READ_URI_PERMISSION);
   }else {getContext().revokeUriPermission(active,Intent.FLAG_GRANT_READ_URI_PERMISSION);if(!URI.equals(active))getContext().revokeUriPermission(URI,Intent.FLAG_GRANT_READ_URI_PERMISSION);}
   boolean present=targetUid>=10000&&getContext().checkUriPermission(active,-1,targetUid,Intent.FLAG_GRANT_READ_URI_PERMISSION)==PackageManager.PERMISSION_GRANTED;
   result.putString("fixture_grant",present?"GRANTED":"ABSENT");return result;
  }finally{Binder.restoreCallingIdentity(identity);}
 }
 @Override public Uri insert(Uri uri,ContentValues values){throw new UnsupportedOperationException("Read only");}
 @Override public int delete(Uri uri,String selection,String[] args){throw new UnsupportedOperationException("Read only");}
 @Override public int update(Uri uri,ContentValues values,String selection,String[] args){throw new UnsupportedOperationException("Read only");}
}
