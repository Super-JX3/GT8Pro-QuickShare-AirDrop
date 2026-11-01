package local.gt8pro.moseybridge;
import android.content.Context;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import java.io.*;
import java.util.Arrays;

/** Own synthetic Downloads row only. No storage permission or personal-file scan. */
final class MediaFixture {
 private static final String PREF="synthetic_fixture", KEY="media_uri";
 private static final String RELATIVE=Environment.DIRECTORY_DOWNLOADS+"/GT8Pro-AirDrop-Tests/";
 static Uri saved(Context c){
  String s=c.getSharedPreferences(PREF,Context.MODE_PRIVATE).getString(KEY,"");
  return s!=null&&s.matches("content://media/external_primary/downloads/[1-9][0-9]*")?Uri.parse(s):null;
 }
 static boolean valid(Context c,Uri uri)throws IOException{
  if(uri==null)return false;
  String[] cols={MediaStore.MediaColumns.DISPLAY_NAME,MediaStore.MediaColumns.SIZE,MediaStore.MediaColumns.OWNER_PACKAGE_NAME,MediaStore.MediaColumns.IS_PENDING,MediaStore.MediaColumns.RELATIVE_PATH};
  try(Cursor cur=c.getContentResolver().query(uri,cols,null,null,null)){
   if(cur==null||cur.getCount()!=1||!cur.moveToFirst()||!FixtureProvider.NAME.equals(cur.getString(0))||cur.getLong(1)!=8192||!c.getPackageName().equals(cur.getString(2))||cur.getInt(3)!=0||!RELATIVE.equals(cur.getString(4)))return false;
  }
  try(InputStream in=c.getContentResolver().openInputStream(uri)){
   if(in==null)return false;
   byte[] actual=in.readNBytes(8193);
   return actual.length==8192&&Arrays.equals(actual,FixtureProvider.bytes());
  }
 }
 static synchronized Uri ensure(Context c)throws IOException{
  Uri old=saved(c);if(old!=null&&valid(c,old))return old;
  ContentValues row=new ContentValues();row.put(MediaStore.MediaColumns.DISPLAY_NAME,FixtureProvider.NAME);row.put(MediaStore.MediaColumns.MIME_TYPE,"text/plain");row.put(MediaStore.MediaColumns.RELATIVE_PATH,RELATIVE);row.put(MediaStore.MediaColumns.IS_PENDING,1);
  Uri uri=c.getContentResolver().insert(MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),row);
  if(uri==null)throw new IOException("Synthetic fixture unavailable");
  boolean complete=false;
  try{
   try(OutputStream stream=c.getContentResolver().openOutputStream(uri,"w")){if(stream==null)throw new IOException("Synthetic fixture unavailable");stream.write(FixtureProvider.bytes());}
   ContentValues done=new ContentValues();done.put(MediaStore.MediaColumns.IS_PENDING,0);
   if(c.getContentResolver().update(uri,done,null,null)!=1||!valid(c,uri)||!c.getSharedPreferences(PREF,Context.MODE_PRIVATE).edit().putString(KEY,uri.toString()).commit())throw new IOException("Synthetic fixture validation failed");
   complete=true;return uri;
  }finally{if(!complete)c.getContentResolver().delete(uri,null,null);}
 }
}
