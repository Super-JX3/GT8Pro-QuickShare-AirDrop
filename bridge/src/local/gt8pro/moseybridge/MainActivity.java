package local.gt8pro.moseybridge;
import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
public final class MainActivity extends Activity {
 @Override public void onCreate(Bundle saved){
  super.onCreate(saved);
  TextView text=new TextView(this);text.setPadding(28,36,28,28);text.setTextSize(17);
  text.setText("GT8 Pro Mosey Bridge 0.11.2（实验版）\n\n"
   +"当前应用仅提供接口兼容，不会自动启动 AirDrop 服务。测试结束后，服务会关闭；手动分享可能无法发现 Apple 设备。\n\n"
   +"当前支持的固件和应用版本受严格校验，后台常驻、长时间发现以及本版本的双向收发仍待验证。\n\n"
   +"如需暂停此桥接，在 LSPosed 中禁用本模块并正常重启手机。不要刷入开发交接 ZIP。\n\n"
   +"下方按钮只用于分享固定的 8 KB 测试文件，不会启用后台服务。");
  android.widget.LinearLayout layout=new android.widget.LinearLayout(this);layout.setOrientation(android.widget.LinearLayout.VERTICAL);
  android.widget.Button share=new android.widget.Button(this);share.setText("系统分享测试（8 KB 合成文件）");share.setOnClickListener(v->startActivity(new android.content.Intent(this,ShareProbeActivity.class)));
  layout.addView(share);layout.addView(text);android.widget.ScrollView scroll=new android.widget.ScrollView(this);scroll.addView(layout);setContentView(scroll);
 }
}
