# DataObjects 0.10 (under DataMapper) still names Fixnum and Bignum, which Ruby 3.2 removed.
# Both are just Integer now, so alias them before the database layer is used.
Object.const_set(:Fixnum, Integer) unless Object.const_defined?(:Fixnum)
Object.const_set(:Bignum, Integer) unless Object.const_defined?(:Bignum)
