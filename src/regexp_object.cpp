#include "natalie.hpp"

namespace Natalie {

Value RegexpObject::initialize(Env *env, Value pattern, Value opts) {
    assert_not_frozen(env);
    if (m_pattern != nullptr)
        env->raise("TypeError", "already initialized regexp");
    if (pattern->is_regexp()) {
        auto other = pattern->as_regexp();
        initialize(env, other->pattern(), other->options());
    } else {
        pattern->assert_type(env, Object::Type::String, "String");
        nat_int_t options = 0;
        if (opts != nullptr) {
            if (opts.is_fast_integer()) {
                options = opts.get_fast_integer();
            } else if(opts->is_integer()) {
                options = opts->as_integer()->to_nat_int_t();
            } else if (opts->is_truthy()) {
                options = 1;
            }
        }

        initialize(env, pattern->as_string()->c_str(), static_cast<int>(options));
    }
    return this;
}

Value RegexpObject::inspect(Env *env) {
    StringObject *out = new StringObject { "/" };
    const char *str = pattern();
    size_t len = strlen(str);
    for (size_t i = 0; i < len; i++) {
        char c = str[i];
        switch (c) {
        case '\n':
            out->append(env, "\\n");
            break;
        case '\t':
            out->append(env, "\\t");
            break;
        case '/':
            out->append(env, "\\/");
            break;
        case '\\':
            if (i < (len - 1) && str[i + 1] == '/') {
                break;
            }
            out->append(env, "\\\\");
            break;
        default:
            out->append_char(c);
        }
    }
    out->append_char('/');
    if (options() & RegexOpts::MultiLine) out->append_char('m');
    if (options() & RegexOpts::IgnoreCase) out->append_char('i');
    if (options() & RegexOpts::Extended) out->append_char('x');
    if (options() & RegexOpts::NoEncoding) out->append_char('n');
    return out;
}

Value RegexpObject::eqtilde(Env *env, Value other) {
    if (other->is_symbol())
        other = other->as_symbol()->to_s(env);
    other->assert_type(env, Object::Type::String, "String");
    Value result = match(env, other);
    if (result->is_nil()) {
        return result;
    } else {
        MatchDataObject *matchdata = result->as_match_data();
        assert(matchdata->size() > 0);
        return IntegerObject::from_size_t(env, matchdata->index(0));
    }
}

Value RegexpObject::match(Env *env, Value other, size_t start_index) {
    if (other->is_symbol())
        other = other->as_symbol()->to_s(env);
    other->assert_type(env, Object::Type::String, "String");
    StringObject *str_obj = other->as_string();

    OnigRegion *region = onig_region_new();
    int result = search(str_obj->c_str(), start_index, region, ONIG_OPTION_NONE);

    Env *caller_env = env->caller();

    if (result >= 0) {
        auto match = new MatchDataObject { region, str_obj };
        caller_env->set_last_match(match);
        return match;
    } else if (result == ONIG_MISMATCH) {
        caller_env->clear_match();
        onig_region_free(region, true);
        return NilObject::the();
    } else {
        caller_env->clear_match();
        onig_region_free(region, true);
        OnigUChar s[ONIG_MAX_ERROR_MESSAGE_LEN];
        onig_error_code_to_str(s, result);
        env->raise("RuntimeError", (char *)s);
    }
}

Value RegexpObject::source(Env *env) {
    return new StringObject { pattern() };
}

Value RegexpObject::to_s(Env *env) {
    StringObject *out = new StringObject { "(" };

    auto is_m = options() & RegexOpts::MultiLine;
    auto is_i = options() & RegexOpts::IgnoreCase;
    auto is_x = options() & RegexOpts::Extended;

    const char *str = pattern();
    size_t len = strlen(str);
    size_t start = 0;

    if (str[start] == '(' && (start + 1) < len && str[start + 1] == '?' && str[len - 1]) {
        /*
        if there is only a single group fully-enclosing the regex, then
        we won't need to wrap it all in another group to specify the options
        */
        bool active = true;
        size_t i;
        bool will_be_m = is_m;
        bool will_be_i = is_i;
        bool will_be_x = is_x;
        for (i = start + 2; i < len && str[i] != ':'; i++) {
            auto c = str[i];
            switch (c)
            {
            case 'm':
                will_be_m = active;
                break;
            case 'i':
                will_be_i = active;
                break;
            case 'x':
                will_be_x = active;
                break;
            case '-':
                if (! active) // this means we've already encountered a '-' which is illegal, so we just to append_options;
                    goto append_options;
                active = false;
                break;
            default:
                goto append_options;
                break;
            }
        }
        {
            size_t open_parentheses = 1;
            // check that the first group is the only top-level group
            for (size_t j = i; j < len; ++j) {
                if (str[j] == ')') 
                    open_parentheses--;
                if (str[j] == '(')
                    open_parentheses++;
                if (open_parentheses == 0 && j != (len - 1))
                    goto append_options;
            }
        }
        is_i = will_be_i;
        is_m = will_be_m;
        is_x = will_be_x;
        len--;
        start = i + 1;
    }
    
    append_options:
    out->append_char('?');
    
    if (is_m) out->append_char('m');
    if (is_i) out->append_char('i');
    if (is_x) out->append_char('x');

    if (! (is_m && is_i && is_x)) out->append_char('-');

    if (! is_m) out->append_char('m');
    if (! is_i) out->append_char('i');
    if (! is_x) out->append_char('x');

    out->append_char(':');

    for (size_t i = start; i < len; i++) {
        char c = str[i];
        switch (c) {
        case '\n':
            out->append(env, "\\n");
            break;
        case '\t':
            out->append(env, "\\t");
            break;
        case '/':
            out->append(env, "\\/");
            break;
        case '\\':
            if (i < (len - 1) && str[i + 1] == '/') {
                break;
            }
            out->append(env, "\\\\");
            break;
        default:
            out->append_char(c);
        }
    }
    out->append_char(')');
    return out;
}

}
