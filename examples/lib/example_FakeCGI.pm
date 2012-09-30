package example_FakeCGI;

use Dancer ':syntax';
use Dancer::Plugin::FakeCGI;
use Data::Dumper;

our $VERSION = '0.1';

#fake_cgi_compile({filename=>""});

#hook 'fake_cgi_before' => sub {
#	my $capture = shift;
#};

get '/' => sub {
    template 'index', {}, {layout => undef};
};

get '/left' => sub {
    template 'left';
};

any '/test_1' => sub {
    fake_cgi_method("test_CGI", "test");
    fake_cgi_as_string;
};

any '/test_2' => sub {
    fake_cgi_method("test_CGI_OOP", "test");
    fake_cgi_as_string;
};

any '/test_3' => sub {
    fake_cgi_file("test_CGI_file.pl");
    fake_cgi_as_string;
};

true;
