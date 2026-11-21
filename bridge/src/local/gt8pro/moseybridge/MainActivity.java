package local.gt8pro.moseybridge;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.content.res.Configuration;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.widget.ScrollView;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class MainActivity extends Activity {
 private TextView status;
 private Button open, check, restart;
 private static final Pattern SNAPSHOT = Pattern.compile(
     "STATUS P2P=(ACTIVE|IDLE|UNKNOWN) BINDER=(PRESENT|ABSENT|UNKNOWN) RADIO=(UP|DOWN|ABSENT|UNKNOWN)");
 @Override public void onCreate(Bundle saved) {
  super.onCreate(saved);
  boolean dark=(getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
      == Configuration.UI_MODE_NIGHT_YES;
  int background=Color.parseColor(dark?"#121418":"#F7F8FC");
  int primary=Color.parseColor(dark?"#F0F1F5":"#1B1B20");
  int secondary=Color.parseColor(dark?"#C3C5CF":"#51545F");
  int accent=Color.parseColor(dark?"#ABC7FF":"#315DA8");
  getWindow().setStatusBarColor(Color.TRANSPARENT);
  getWindow().setNavigationBarColor(background);
  getWindow().getDecorView().setSystemUiVisibility(dark?0:
      View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);

  ScrollView scroll=new ScrollView(this);
  scroll.setFillViewport(true);
  scroll.setBackgroundColor(background);
  scroll.setOnApplyWindowInsetsListener((view,insets)-> {
   android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
   view.setPadding(bars.left,bars.top,bars.right,bars.bottom);
   return insets;
  });
  LinearLayout outer=new LinearLayout(this);
  outer.setGravity(Gravity.CENTER);
  outer.setPadding(dp(24),dp(32),dp(24),dp(32));
  LinearLayout layout=new LinearLayout(this);
  layout.setOrientation(LinearLayout.VERTICAL);
  layout.setGravity(Gravity.CENTER_HORIZONTAL);
  int contentWidth=Math.min(420,Math.max(0,getResources().getConfiguration().screenWidthDp-48));
  outer.addView(layout,new LinearLayout.LayoutParams(dp(contentWidth),LinearLayout.LayoutParams.WRAP_CONTENT));
  TextView title=new TextView(this);
  title.setText("Quick Share 服务");
  title.setTextSize(24);
  title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
  title.setTextColor(primary);
  title.setGravity(Gravity.CENTER);
  layout.addView(title,new LinearLayout.LayoutParams(-1,-2));
  status=new TextView(this);
  status.setTextSize(16);
  status.setTextColor(secondary);
  status.setGravity(Gravity.CENTER);
  status.setLineSpacing(dp(3),1f);
  status.setText("可直接打开 Quick Share，保留当前连接。若苹果设备无法发现手机，可检查直连、服务和无线接口状态。");
  LinearLayout.LayoutParams info=new LinearLayout.LayoutParams(-1,-2);
  info.topMargin=dp(20);
  layout.addView(status,info);

  open=addButton(layout,"打开 Quick Share",28);
  open.setTextColor(dark?Color.parseColor("#102B58"):Color.WHITE);
  open.setBackgroundTintList(ColorStateList.valueOf(accent));
  open.setOnClickListener(v -> openQuickShare());
  check=addButton(layout,"检查 AirDrop 状态",8);
  check.setOnClickListener(v -> runModule(false));
  restart=addButton(layout,"断开直连并恢复 AirDrop",8);
  restart.setOnClickListener(v -> new AlertDialog.Builder(this)
    .setTitle("断开当前 Wi-Fi 直连？")
    .setMessage("这可能断开 OPPO 平板互联或其他直连设备。模块会先核验分享传输和服务是否空闲。")
    .setNegativeButton("取消", null)
    .setPositiveButton("断开直连并恢复", (dialog,which) -> runModule(true)).show());
  scroll.addView(outer,new ScrollView.LayoutParams(-1,-1));
  setContentView(scroll);
  scroll.requestApplyInsets();
 }

 private int dp(float value) {
  return (int)(value*getResources().getDisplayMetrics().density+0.5f);
 }

 private Button addButton(LinearLayout layout,String label,int topMargin) {
  Button button=new Button(this);
  button.setText(label);
  button.setAllCaps(false);
  LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,dp(56));
  params.topMargin=dp(topMargin);
  layout.addView(button,params);
  return button;
 }

 private void openQuickShare() {
  try {
   startActivity(new Intent().setComponent(new ComponentName("com.google.android.gms",
       "com.google.android.gms.nearby.sharing.main.MainActivity")));
  } catch(Exception ignored) {
   status.setText("无法打开 Quick Share。请从系统分享页面打开。");
  }
 }

 private void enableActions(boolean enabled) {
  open.setEnabled(enabled);
  check.setEnabled(enabled);
  restart.setEnabled(enabled);
 }

 private void runModule(boolean reclaim) {
  enableActions(false);
  status.setText(reclaim?"正在检查服务和传输状态…":"正在读取当前状态…");
  new Thread(() -> {
   String response="";
   boolean succeeded=false;
   Process process=null;
   try {
    process=new ProcessBuilder("su","-c",
        "sh /data/adb/modules/gt8pro.mosey.integrated/payload/restart-service.sh "+
        (reclaim?"reclaim":"status")).redirectErrorStream(true).start();
    if(process.waitFor(reclaim?90:18,TimeUnit.SECONDS)) {
     try(InputStream in=process.getInputStream()) {
      ByteArrayOutputStream out=new ByteArrayOutputStream();
      byte[] bytes=new byte[256];
      while(out.size()<4096) {
       int n=in.read(bytes,0,Math.min(bytes.length,4096-out.size()));
       if(n<0)break;
       out.write(bytes,0,n);
      }
      response=out.toString("UTF-8").trim();
     }
     succeeded=process.exitValue()==0;
    } else {
     response="TIMEOUT";
    }
   } catch(InterruptedException e) {
    Thread.currentThread().interrupt();
   } catch(Exception ignored) {
    // A denied root request or malformed response cannot confirm any state.
   } finally {
    if(process!=null)process.destroy();
   }
   final String result=response;
   final boolean ok=succeeded;
   runOnUiThread(() -> {
    if(isFinishing() || isDestroyed())return;
    enableActions(true);
    if(reclaim)showRecovery(result,ok);
    else showSnapshot(result,ok);
   });
  },"GT8-ModuleAction").start();
 }

 private void showRecovery(String result,boolean succeeded) {
  if(succeeded && result.equals("RESTART_READY")) {
   status.setText("恢复检查通过，正在打开 Quick Share。请在苹果设备上确认能否发现手机。");
   openQuickShare();
   return;
  }
  switch(result) {
   case "TRANSFER_BUSY":status.setText("分享传输中或空闲状态无法确认。请稍后再试。");break;
   case "SERVICE_ACTIVE":status.setText("分享服务尚未退出，或其状态无法确认。请关闭 Quick Share，稍后再试。");break;
   case "P2P_RELEASE_FAILED":status.setText("无法确认 Wi-Fi 直连已释放。请检查平板连接状态。");break;
   case "MODULE_UNAVAILABLE":status.setText("无法访问配套模块。请检查模块是否启用及 Root 授权。");break;
   case "TIMEOUT":status.setText("恢复操作超时。请检查平板连接状态和 Root 授权。");break;
   default:status.setText("恢复检查未通过。请检查配套模块及 Root 授权。");
  }
 }

 private void showSnapshot(String result,boolean succeeded) {
  Matcher match=SNAPSHOT.matcher(result);
  if(!succeeded || !match.matches()) {
   status.setText("无法读取状态。请检查配套模块及 Root 授权。");
   return;
  }
  String p2p=match.group(1), binder=match.group(2), radio=match.group(3);
  String directLabel=switch(p2p) {
   case "ACTIVE" -> "有活动直连组";
   case "IDLE" -> "无活动直连组";
   default -> "未确认";
  };
  String binderLabel=switch(binder) {
   case "PRESENT" -> "已注册";
   case "ABSENT" -> "未注册";
   default -> "未确认";
  };
  String radioLabel=switch(radio) {
   case "UP" -> "已启用";
   case "DOWN" -> "存在，未启用";
   case "ABSENT" -> "未出现";
   default -> "未确认";
  };
  String hint="设备是否可见，请在 iPhone 或 Mac 上确认。";
  if(p2p.equals("ACTIVE") && binder.equals("PRESENT") &&
      (radio.equals("DOWN") || radio.equals("ABSENT"))) {
   hint="分享可能在等待 Wi-Fi 直连释放。可保留连接，稍后再检查。";
  }
  status.setText("当前设备状态\nWi-Fi 直连："+directLabel+"\n分享服务（Binder）："+binderLabel+
      "\nAirDrop 无线接口："+radioLabel+"\n\n"+hint);
 }
}
