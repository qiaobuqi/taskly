package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
)

// StringArray persists a []string as a JSON column. MySQL has no native array type
// (unlike Postgres text[]), so we serialize to JSON. Because the underlying type is
// []string, it still marshals to a plain JSON array in API responses.
type StringArray []string

func (a StringArray) Value() (driver.Value, error) {
	if a == nil {
		return "[]", nil
	}
	b, err := json.Marshal([]string(a))
	if err != nil {
		return nil, err
	}
	return string(b), nil
}

func (a *StringArray) Scan(src interface{}) error {
	if src == nil {
		*a = StringArray{}
		return nil
	}
	var data []byte
	switch v := src.(type) {
	case []byte:
		data = v
	case string:
		data = []byte(v)
	default:
		return errors.New("StringArray: unsupported Scan source")
	}
	if len(data) == 0 {
		*a = StringArray{}
		return nil
	}
	return json.Unmarshal(data, (*[]string)(a))
}
