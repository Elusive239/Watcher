module main2;
import std::io::path;
import watcher;

fn void main(String[] args) => @pool() {
    String input = "./.vscode/settings.json";
    String? output = watcher::to_verified_path(input);
    if(catch err = output) err?!!; 
    io::printfn("input: '%s'\noutput '%s'", input,output);
}