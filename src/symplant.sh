#! /usr/bin/env bash

# Project directory
PROJECT_DIR=${1:-.}

[[ -s "$PROJECT_DIR/symfony.lock" ]] || {
  >&2 echo "Error: not a Symfony project directory."
  exit 1
}

echo "Generating diagram..."

UML_FILE="${PROJECT_DIR}/classes.plantuml"
PNG_FILE="${PROJECT_DIR}/classes.png"

HEADER="$(cat << EOB
@startuml
!define table(x) entity x << (T, white) >>
!define primary_key(x) <b><&key> x</b>
!define column(x) <&media-record> x
!define foreign_key(x) <&key> x
EOB
)"

FOOTER="@enduml"

declare -a RELATIONS

read_entity() {
  # Get entity name, fields and data types
  PRIMARY='^#\[ORM\\Id\]$'
  COLUMN='^#\[ORM\\Column(\(.+\))?\]$'
  FOREIGN1='^#\[ORM\\OneToMany(\(.+\))?\]$'
  FOREIGN2='^#\[ORM\\ManyToOne(\(.+\))?\]$'
  CLASS='^class[[:blank:]]([A-Za-z]+)([[:space:]].*)?$'
  FIELD='^private[[:blank:]]\??([A-Za-z0-9]+)?[[:blank:]]?\$([A-Za-z0-9]+)'

  while read -r line; do

    [[ $line =~ $CLASS ]] && {
      entity="${BASH_REMATCH[1]}"
      echo -e "\ntable( ${entity,,} ) {" >> "$UML_FILE"
    }

    [[ $line =~ $PRIMARY ]] && primary=1
    [[ $line =~ $FOREIGN1 ]] && foreign1=1
    [[ $line =~ $FOREIGN2 ]] && foreign2=1

    [[ $line =~ $FIELD ]] && {
      field="${BASH_REMATCH[2]}"
      datatype="${BASH_REMATCH[1]}"

      # echo "$field : $datatype PK($primary) FK1($foreign1) FK2($foreign2)"

      [[ $primary ]] && {
        echo "  primary_key( $field ) : $datatype" >> "$UML_FILE"
        unset primary
        continue
      }
      [[ $foreign1 ]] && {
        [[ $datatype == "Collection" ]] && {
          unset foreign1
          continue
        }
        echo "  foreign_key( $field ) : $datatype <<FK>>" >> "$UML_FILE"
        RELATIONS+=("${entity,,} }||--| ${datatype,,}")
        unset foreign1
        continue
      }
      [[ $foreign2 ]] && {
        [[ $datatype == "Collection" ]] && {
          unset foreign2
          continue
        }
        echo "  foreign_key( $field ) : $datatype <<FK>>" >> "$UML_FILE"
        RELATIONS+=("${entity,,} }|--|| ${datatype,,}")
        unset foreign2
        continue
      }
      
      echo "  column( $field ) : $datatype" >> "$UML_FILE"
    }
  done < $1
  echo "}" >> "$UML_FILE"
}

echo "$HEADER" > "$UML_FILE"

for file in $PROJECT_DIR/src/Entity/*; do
  read_entity "$file"
done

for relation in "${RELATIONS[@]}"; do
  echo "$relation" >> "$UML_FILE"
done

echo "$FOOTER" >> "$UML_FILE"

echo "Exporting..."

plantuml "$UML_FILE" || {
  >&2 echo "An error occured."
  exit 1
}

echo "Done."

feh -Z "$PNG_FILE"
