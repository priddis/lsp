pub const Fields = struct {
	pub const name: u16 = 20;
	pub const declarator: u16 = 8;
	pub const object: u16 = 21;
	pub const parameters: u16 = 25;
	pub const body: u16 = 4;
	pub const type: u16 = 36;
	pub const declarator: u16 = 8;
};
pub const Symbols = struct {
	pub const field_declaration: u16 = 250;
	pub const local_variable_declaration: u16 = 279;
	pub const method_invocation: u16 = 168;
	pub const formal_parameter: u16 = 275;
	pub const formal_parameters: u16 = 274;
	pub const package_declaration: u16 = 227;
	pub const import_declaration: u16 = 228;
	pub const class_declaration: u16 = 234;
	pub const method_declaration: u16 = 280;
	pub const class_body: u16 = 243;
	pub const type_identifier: u16 = 321;
	pub const variable_declarator: u16 = 261;
	pub const array_type: u16 = 269;
};
