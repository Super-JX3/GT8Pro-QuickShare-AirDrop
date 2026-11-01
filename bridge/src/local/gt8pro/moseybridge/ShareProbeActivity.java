package local.gt8pro.moseybridge;
import android.app.Activity;
import android.os.Bundle;
import android.content.Intent;
import android.content.ClipData;
public final class ShareProbeActivity extends Activity {
 @Override public void onCreate(Bundle saved){
  super.onCreate(saved);if(saved!=null){finish();return;}
  if(getIntent()!=null&&getIntent().getBooleanExtra("revoke_fixture",false)){
   android.net.Uri media=MediaFixture.saved(this);
   if(media!=null)revokeUriPermission(media,Intent.FLAG_GRANT_READ_URI_PERMISSION);
   revokeUriPermission(FixtureProvider.URI,Intent.FLAG_GRANT_READ_URI_PERMISSION);
   finish();return;
  }
  final android.net.Uri fixture;
  try{fixture=MediaFixture.ensure(this);}catch(Exception failure){android.util.Log.i("GT8Fixture","FIXTURE_MEDIASTORE=UNAVAILABLE");finish();return;}
  grantUriPermission("com.google.android.mosey",fixture,Intent.FLAG_GRANT_READ_URI_PERMISSION);
  grantUriPermission("com.google.android.gms",fixture,Intent.FLAG_GRANT_READ_URI_PERMISSION);
  Intent send=new Intent(Intent.ACTION_SEND).setType("text/plain");
  send.putExtra(Intent.EXTRA_STREAM,fixture);
  send.setClipData(ClipData.newRawUri("GT8Pro synthetic fixture",fixture));
  send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
  startActivityForResult(Intent.createChooser(send,"GT8Pro 合成文件测试"),42);
 }
 @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==42)finish();}
}
