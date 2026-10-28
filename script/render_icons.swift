import AppKit
import CoreGraphics

let root = URL(fileURLWithPath:CommandLine.arguments[1])
let assets = root.appendingPathComponent("Assets/Brand")
let outputs = root.appendingPathComponent("outputs")
let fm = FileManager.default
try fm.createDirectory(at:assets,withIntermediateDirectories:true)
let navy = NSColor(calibratedRed:0.035,green:0.16,blue:0.22,alpha:1)
let mint = NSColor(calibratedRed:0.40,green:0.96,blue:0.79,alpha:1)
func rounded(_ rect:NSRect,_ radius:CGFloat,_ color:NSColor) {
 color.setFill(); NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill()
}
func mark(template:Bool = false, active:Bool = false) {
 let ink = template ? NSColor.black : NSColor(calibratedWhite:0.98,alpha:1)
 // A keyboard deck spans the two abutments of a bridge.
 let bridge = NSBezierPath()
 bridge.move(to:NSPoint(x:256,y:305)); bridge.line(to:NSPoint(x:256,y:510))
 bridge.line(to:NSPoint(x:768,y:510)); bridge.line(to:NSPoint(x:768,y:305))
 bridge.line(to:NSPoint(x:664,y:305))
 bridge.curve(to:NSPoint(x:360,y:305),controlPoint1:NSPoint(x:664,y:532),controlPoint2:NSPoint(x:360,y:532))
 bridge.close(); ink.setFill(); bridge.fill()
 let deck=NSBezierPath(roundedRect:NSRect(x:202,y:496,width:620,height:228),xRadius:54,yRadius:54)
 deck.windingRule = .evenOdd
 var holes:[NSRect] = (0..<6).map { NSRect(x:256+CGFloat($0)*88,y:631,width:62,height:44) }
 holes += [NSRect(x:256,y:550,width:100,height:40),NSRect(x:382,y:550,width:260,height:40),NSRect(x:668,y:550,width:100,height:40)]
 for hole in holes { deck.append(NSBezierPath(roundedRect:hole,xRadius:10,yRadius:10)) }
 ink.setFill(); deck.fill()
 if !template { for hole in holes { rounded(hole,10,navy) } }
 if !template {
  let arch=NSBezierPath(); arch.move(to:NSPoint(x:381,y:318))
  arch.curve(to:NSPoint(x:643,y:318),controlPoint1:NSPoint(x:381,y:501),controlPoint2:NSPoint(x:643,y:501))
  arch.lineWidth=22; arch.lineCapStyle = .round; mint.setStroke(); arch.stroke()
 }
 if active { rounded(NSRect(x:820,y:212,width:112,height:112),56,ink) }
}
func canvas(_ size:Int,draw:()->Void)->NSBitmapImageRep {
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
 NSGraphicsContext.current!.cgContext.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 draw(); NSGraphicsContext.restoreGraphicsState(); return bitmap
}
func appIcon() {
 let tile=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:202,yRadius:202)
 NSGraphicsContext.saveGraphicsState()
 let shadow=NSShadow(); shadow.shadowColor=NSColor.black.withAlphaComponent(0.20);shadow.shadowBlurRadius=22;shadow.shadowOffset=NSSize(width:0,height:-10);shadow.set()
 navy.setFill();tile.fill();NSGraphicsContext.restoreGraphicsState()
 NSGradient(starting:NSColor(calibratedRed:0.04,green:0.31,blue:0.36,alpha:1),ending:navy)!.draw(in:tile,angle:-80)
 NSGraphicsContext.saveGraphicsState(); tile.addClip()
 let gleam=NSBezierPath(ovalIn:NSRect(x:-220,y:500,width:1000,height:1000))
 NSColor.white.withAlphaComponent(0.035).setFill();gleam.fill();NSGraphicsContext.restoreGraphicsState()
 NSColor.white.withAlphaComponent(0.14).setStroke();tile.lineWidth=2;tile.stroke()
 mark()
}
let iconset=assets.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at:iconset,withIntermediateDirectories:true)
for base in [16,32,128,256,512] {
 for scale in [1,2] {
  let rep=canvas(base*scale,draw:appIcon)
  try rep.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent("icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
 }
}
try canvas(1024,draw:appIcon).representation(using:.png,properties:[:])!.write(to:outputs.appendingPathComponent("keybridge-icon.png"))
// Vector PDF templates remain crisp at both menu bar backing scales.
for active in [false,true] {
 let data=NSMutableData(); var box=CGRect(x:0,y:0,width:20,height:20)
 let context=CGContext(consumer:CGDataConsumer(data:data)!,mediaBox:&box,nil)!
 context.beginPDFPage(nil);context.scaleBy(x:20/1024,y:20/1024)
 // Zoom the glyph into the menu bar canvas without the app tile.
 context.translateBy(x:-90,y:-80);context.scaleBy(x:1.15,y:1.15)
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
 mark(template:true,active:active)
 NSGraphicsContext.restoreGraphicsState();context.endPDFPage();context.closePDF()
 try (data as Data).write(to:assets.appendingPathComponent(active ? "MenuBarActive.pdf" : "MenuBar.pdf"))
}
