#!/usr/bin/env swift
// Render the Switch app icon to a 1024×1024 PNG.
// Three stacked rounded windows offset diagonally on aubergine, with the
// front window getting macOS-style traffic-light dots.
//
// Run: swift tools/render-icon.swift > tools/icon-1024.png

import AppKit

let size = NSSize(width: 1024, height: 1024)
let img = NSImage(size: size)
img.lockFocus()

// background (aubergine)
NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.20, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 200, yRadius: 200).fill()

func roundRect(_ rect: NSRect, fill: NSColor, radius: CGFloat = 36) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

let creamDim = NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.74, alpha: 1)
let cream    = NSColor(calibratedRed: 0.93, green: 0.90, blue: 0.83, alpha: 1)
let rose     = NSColor(calibratedRed: 0.93, green: 0.74, blue: 0.62, alpha: 1)

// back window
roundRect(NSRect(x: 200, y: 280, width: 540, height: 360), fill: creamDim)
// middle window (offset down-right)
roundRect(NSRect(x: 280, y: 220, width: 540, height: 360), fill: cream)
// front window (further down-right) in rose gold
let front = NSRect(x: 360, y: 160, width: 540, height: 360)
roundRect(front, fill: rose)

// traffic-light dots on the front window's title bar
let dotY = front.maxY - 36
NSColor.systemRed.setFill();    NSBezierPath(ovalIn: NSRect(x: front.minX + 24,  y: dotY - 12, width: 24, height: 24)).fill()
NSColor.systemYellow.setFill(); NSBezierPath(ovalIn: NSRect(x: front.minX + 60,  y: dotY - 12, width: 24, height: 24)).fill()
NSColor.systemGreen.setFill();  NSBezierPath(ovalIn: NSRect(x: front.minX + 96,  y: dotY - 12, width: 24, height: 24)).fill()

img.unlockFocus()

let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
FileHandle.standardOutput.write(png)
