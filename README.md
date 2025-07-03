# Watcher

A filesystem watcher written in [C3](https://c3-lang.org/), based off of [x-watcher](https://github.com/nikp123/x-watcher/tree/main) (created by [nikp123](https://github.com/nikp123)), a filesystem watcher written in C. 

Currently only works with full paths (limitation carryover from x-watcher). Support for other kinds of paths is in progress.

> [!WARNING]
> This is an experimental library, with possibly unstable features. Use at your own risk.

## Supported Platforms:  
[#] Windows!  
[#] Linux!  
[-] Anything Else!  

If someone wished to *add support* for another platform I would be obliged to add it here... 

## Dependencies:  
- C3 Standrd Library  
- Linux Only: gcc-multilib  

## To Use:

I recommend looking at the [example](src/example.c3), it's simple to use. 

## Thanks!

Thanks to [@nikp123](https://github.com/nikp123) for creating x-watcher!

Thanks a bunch to [@ashindigo](https://github.com/ashindigo) for helping to debug the linux side of things.