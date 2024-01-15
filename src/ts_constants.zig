pub const Fields = struct {
	pub const name: u16 = 20;
	pub const declarator: u16 = 8;
	pub const object: u16 = 21;
	pub const parameters: u16 = 25;
	pub const body: u16 = 4;
};
pub const Symbols = struct {
	pub const field_declaration: u16 = 250;
	pub const local_variable_declaration: u16 = 279;
	pub const method_invocation: u16 = 168;
	pub const formal_parameter: u16 = 275;
};
