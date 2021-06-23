/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header defining preprocessor conditional values that control the configuration of the app
*/

// When enabled, rendering occurs on the main application thread.
// This can make responding to UI events during redraw simpler
// to manage because UI calls usually must occur on the main thread.
// When disabled, rendering occurs on a background thread, allowing
// the UI to respond more quickly in some cases because events can be 
// processed asynchronously from potentially CPU-intensive rendering code.
#define RENDER_ON_MAIN_THREAD 0

// When enabled, the view continually animates and renders
// frames 60 times a second.  When disabled, rendering is event
// based, occurring when a UI event requests a redraw.
#define ANIMATION_RENDERING   1

// 打开的话, 只要view尺寸发生变化，drawable绘制对象的大小会自动更新
// 关闭的话，可以在view类以外的地方，显式更新drawable绘制对象的尺寸
#define AUTOMATICALLY_RESIZE  1

// 打开的话, render会创建深度buffer 并且 通过render pass描述符  即将渲染的绘制对象的纹理上
// 同时允许深度测试
#define CREATE_DEPTH_BUFFER   1

