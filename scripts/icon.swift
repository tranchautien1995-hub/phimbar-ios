import AppKit
let directory=CommandLine.arguments[1]
for (name,size) in [("Icon60@2x.png",120),("Icon60@3x.png",180)] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let n=CGFloat(size)
    NSColor(calibratedRed:0.055,green:0.10,blue:0.19,alpha:1).setFill()
    NSBezierPath(rect:NSRect(x:0,y:0,width:n,height:n)).fill()
    NSColor(calibratedRed:0.21,green:0.57,blue:1,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:n*0.16,y:n*0.22,width:n*0.68,height:n*0.58),xRadius:n*0.20,yRadius:n*0.20).fill()
    let tail=NSBezierPath();tail.move(to:NSPoint(x:n*0.27,y:n*0.31));tail.line(to:NSPoint(x:n*0.23,y:n*0.12));tail.line(to:NSPoint(x:n*0.45,y:n*0.25));tail.close();tail.fill()
    let arrow=NSBezierPath();arrow.appendArc(withCenter:NSPoint(x:n*0.5,y:n*0.51),radius:n*0.17,startAngle:40,endAngle:320,clockwise:false)
    arrow.lineWidth=n*0.055;arrow.lineCapStyle = .round;NSColor.white.setStroke();arrow.stroke()
    let head=NSBezierPath();head.move(to:NSPoint(x:n*0.63,y:n*0.65));head.line(to:NSPoint(x:n*0.65,y:n*0.49));head.line(to:NSPoint(x:n*0.50,y:n*0.56));head.close();NSColor.white.setFill();head.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory+"/"+name))
}
