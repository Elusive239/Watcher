module main;
import std::io::path;

fn String? verified_path(String input) => @pool(){
    Path path = {
        .path_string =  path::normalize( input.copy(tmem))!,
    };

    if(!path.is_absolute()!){
        path = path.absolute(tmem)!;
    }

    DString tmp;
    tmp.new_with_capacity(mem, path.path_string.len+1);
    tmp.appendf("%s\0",path.path_string);
    return tmp.str_view();
}

fn void main(String[] args) => @pool() {
    String input = "./.vscode/settings.json";
    String? output = verified_path(input);
    if(catch err = output) err?!!; 
    io::printfn("input: '%s'\noutput '%s'", input,output);
}